#!/usr/bin/env bash
# Clone kg-template-vm into two test VMs on the isolated kg-isolated-network and run the
# P0-U5 in-VM isolation checks. Usage: clone-test-vms.sh create | test | destroy
set -euo pipefail
V="virsh -c qemu:///system"
KEY=${KG_LAB_KEY:-$HOME/.ssh/kubeguard-lab.pub}
HERE=$(cd "$(dirname "$0")" && pwd)
NODES="kg-test-1-vm kg-test-2-vm"

vm_ip() { $V domifaddr "$1" --source lease 2>/dev/null | awk '/ipv4/ {sub("/.*","",$4); print $4; exit}'; }
vm_ssh() {
  ssh -i "${KEY%.pub}" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
      ubuntu@"$1" "${@:2}"
}
wait_ip_ssh() {
  for _ in $(seq 1 60); do
    ip=$(vm_ip "$1"); [ -n "$ip" ] && vm_ssh "$ip" true 2>/dev/null && { echo "$ip"; return 0; }
    sleep 5
  done
  return 1
}
wait_off() { for _ in $(seq 1 30); do [ "$($V domstate "$1")" = "shut off" ] && return 0; sleep 2; done; return 1; }

make_seed() {
  # unique instance-id makes cloud-init treat the clone as a new instance and
  # regenerate its network config for the clone's own MAC address
  local n=$1 tmp; tmp=$(mktemp -d)
  sed -e "s|@SSH_PUBKEY@|$(cat "$KEY")|" -e "s|@NAME@|${n%-vm}|" "$HERE/../cloud-init/clone-user-data.tpl" > "$tmp/user-data"
  printf 'instance-id: %s-%s\nlocal-hostname: %s\n' "$n" "$(date +%s)" "$n" > "$tmp/meta-data"
  cloud-localds "$tmp/seed.iso" "$tmp/user-data" "$tmp/meta-data"
  $V vol-create-as kg-storage-pool "${n%-vm}-seed.iso" "$(stat -c %s "$tmp/seed.iso")" --format raw
  $V vol-upload --pool kg-storage-pool "${n%-vm}-seed.iso" "$tmp/seed.iso"
  rm -rf "$tmp"
}

swap_seed() {
  local n=$1 tgt path
  tgt=$($V domblklist "$n" --details | awk '$2=="cdrom" {print $3; exit}')
  path=$($V vol-path --pool kg-storage-pool "${n%-vm}-seed.iso")
  $V change-media "$n" "$tgt" "$path" --config --update 2>/dev/null || $V change-media "$n" "$tgt" "$path" --config --insert
}

create() {
  for n in $NODES; do
    virt-clone --connect qemu:///system --original kg-template-vm --name "$n" --auto-clone >/dev/null
    mac=$($V domiflist "$n" | awk '/kg-internet-access-network/ {print $5}')
    $V detach-interface "$n" network --mac "$mac" --config
    $V attach-interface "$n" network kg-isolated-network --model virtio --config
    make_seed "$n"
    swap_seed "$n"
    $V start "$n" >/dev/null
    ip=$(wait_ip_ssh "$n") || { echo "FAIL  $n unreachable"; exit 1; }
    # new machine-id so the DHCP client identifier differs between clones
    vm_ssh "$ip" "sudo truncate -s0 /etc/machine-id && sudo rm -f /var/lib/dbus/machine-id && sudo poweroff" 2>/dev/null || true
    wait_off "$n"
  done
  for n in $NODES; do $V start "$n" >/dev/null; done
  for n in $NODES; do echo "$n $(wait_ip_ssh "$n")"; done
}

test_nodes() {
  A=$(vm_ip kg-test-1-vm); B=$(vm_ip kg-test-2-vm)
  [ "$A" != "$B" ] || { echo "FAIL  both VMs have the same address $A"; exit 1; }
  "$HERE/test-isolation.sh" "$A" "$B" ubuntu
}

destroy() {
  for n in $NODES; do
    $V destroy "$n" 2>/dev/null || true
    $V undefine "$n" --remove-all-storage --snapshots-metadata 2>/dev/null || true
    $V vol-delete --pool kg-storage-pool "${n%-vm}-seed.iso" 2>/dev/null || true
  done
}

case "${1:-}" in
  create) create ;; test) test_nodes ;; destroy) destroy ;;
  *) echo "usage: $0 create|test|destroy"; exit 2 ;;
esac
