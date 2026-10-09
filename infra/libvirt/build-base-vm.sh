#!/usr/bin/env bash
# P0-U6: build the base VM, snapshot it and test the restore.
# Usage: build-base-vm.sh create | snapshot | restore-test | destroy
# Resources are kept minimal (1 vCPU, 1 GiB RAM, 10 GiB thin disk).
set -euo pipefail
V="virsh -c qemu:///system"
POOL=kg-images
VM=kg-base
BACKING=noble-base.img
DISK=$VM.qcow2
SEED=$VM-seed.iso
SNAP=base-clean
KEY=${KG_LAB_KEY:-$HOME/.ssh/kubeguard-lab.pub}
HERE=$(cd "$(dirname "$0")" && pwd)
CI=$HERE/../cloud-init

create() {
  netinfo=$($V net-info kg-build 2>/dev/null || true)
  grep -q 'Active:.*yes' <<<"$netinfo" || { echo "kg-build is not active (make build-net-up)"; exit 1; }
  $V vol-info --pool $POOL $BACKING >/dev/null || { echo "missing $BACKING in pool $POOL"; exit 1; }
  [ -r "$KEY" ] || { echo "public key $KEY not readable"; exit 1; }
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  sed "s|@SSH_PUBKEY@|$(cat "$KEY")|" "$CI/user-data.tpl" > "$tmp/user-data"
  cp "$CI/meta-data" "$tmp/meta-data"
  cloud-localds "$tmp/seed.iso" "$tmp/user-data" "$tmp/meta-data"
  $V vol-create-as $POOL $DISK 10G --format qcow2 --backing-vol $BACKING --backing-vol-format qcow2
  $V vol-create-as $POOL $SEED "$(stat -c %s "$tmp/seed.iso")" --format raw
  $V vol-upload --pool $POOL $SEED "$tmp/seed.iso"
  virt-install --connect qemu:///system --name $VM --import \
    --memory 1024 --vcpus 1 --os-variant ubuntu24.04 \
    --disk vol=$POOL/$DISK,bus=virtio \
    --disk vol=$POOL/$SEED,device=cdrom \
    --network network=kg-build --graphics none --noautoconsole
  echo "Provisioning runs on first boot; the VM powers off when done. Check: virsh -c qemu:///system domstate $VM"
}

snapshot() {
  [ "$($V domstate $VM)" = "shut off" ] || { echo "$VM must be shut off first"; exit 1; }
  $V snapshot-create-as $VM $SNAP "clean base image after provisioning"
  $V snapshot-list $VM
}

vm_ip() { $V domifaddr $VM --source lease 2>/dev/null | awk '/ipv4/ {sub("/.*","",$4); print $4; exit}'; }

vm_ssh() {
  ssh -i "${KEY%.pub}" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
      ubuntu@"$1" "${@:2}"
}

wait_ssh() {
  for _ in $(seq 1 60); do
    ip=$(vm_ip); [ -n "$ip" ] && vm_ssh "$ip" true 2>/dev/null && { echo "$ip"; return 0; }
    sleep 5
  done
  return 1
}

wait_off() {
  for _ in $(seq 1 30); do [ "$($V domstate $VM)" = "shut off" ] && return 0; sleep 2; done
  return 1
}

restore_test() {
  # 1. boot, write a marker, shut down  2. revert to the snapshot  3. boot, marker must be gone
  $V start $VM >/dev/null
  ip=$(wait_ssh) || { echo "FAIL  VM did not become reachable"; exit 1; }
  vm_ssh "$ip" "touch ~/restore-marker && test -f ~/restore-marker" && echo "PASS  marker written after boot"
  vm_ssh "$ip" "sudo poweroff" 2>/dev/null || true
  wait_off || { echo "FAIL  VM did not shut down"; exit 1; }
  $V snapshot-revert $VM $SNAP
  $V start $VM >/dev/null
  ip=$(wait_ssh) || { echo "FAIL  VM unreachable after revert"; exit 1; }
  if vm_ssh "$ip" "test -f ~/restore-marker"; then
    echo "FAIL  marker still present after revert"; fail=1
  else
    echo "PASS  marker gone after revert (snapshot $SNAP restores)"; fail=0
  fi
  vm_ssh "$ip" "sudo poweroff" 2>/dev/null || true
  wait_off || true
  exit ${fail:-1}
}

destroy() {
  $V destroy $VM 2>/dev/null || true
  $V undefine $VM --snapshots-metadata 2>/dev/null || true
  $V vol-delete --pool $POOL $DISK 2>/dev/null || true
  $V vol-delete --pool $POOL $SEED 2>/dev/null || true
}

case "${1:-}" in
  create) create ;;
  snapshot) snapshot ;;
  restore-test) restore_test ;;
  destroy) destroy ;;
  *) echo "usage: $0 create|snapshot|restore-test|destroy"; exit 2 ;;
esac
