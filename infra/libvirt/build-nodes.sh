#!/usr/bin/env bash
# P1-U1: create, test, isolate, snapshot and destroy the cluster node VMs.
# Usage: build-nodes.sh create | status | test | isolate | snapshot | destroy
# Nodes are listed in nodes.conf. Names follow docs/naming.md.
set -euo pipefail
V="virsh -c qemu:///system"
POOL=kg-storage-pool
TEMPLATE_DISK=kg-template-disk.qcow2
ISOLATED=kg-isolated-network
INTERNET=kg-internet-access-network
KEY=${KG_LAB_KEY:-$HOME/.ssh/kubeguard-lab.pub}
HERE=$(cd "$(dirname "$0")" && pwd)
CI=$HERE/../cloud-init
CONF=${NODES_CONF:-$HERE/nodes.conf}

rows() { grep -v '^[[:space:]]*#' "$CONF" | grep -v '^[[:space:]]*$'; }

ssh_node() {
  ssh -i "${KEY%.pub}" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
      ubuntu@"$1" "${@:2}"
}

wait_ssh() {  # wait_ssh <ip> [seconds]
  local t=$(( ${2:-300} / 5 ))
  for _ in $(seq 1 "$t"); do ssh_node "$1" true 2>/dev/null && return 0; sleep 5; done
  return 1
}

wait_off() {  # wait_off <vm>
  for _ in $(seq 1 60); do [ "$($V domstate "$1")" = "shut off" ] && return 0; sleep 2; done
  return 1
}

ok()  { echo "PASS  $*"; }
bad() { echo "FAIL  $*"; FAILED=1; }

reserve_addresses() {
  local xml; xml=$($V net-dumpxml "$ISOLATED")
  while read -r name role ip imac emac vcpus mem disk; do
    if grep -q "$imac" <<<"$xml"; then continue; fi
    $V net-update "$ISOLATED" add ip-dhcp-host "<host mac='$imac' name='$name' ip='$ip'/>" --live --config >/dev/null
    echo "reserved $ip for $name"
  done < <(rows)
}

make_seed() {  # make_seed <name> <isolated_mac> <internet_mac>
  local name=$1 imac=$2 emac=$3 tmp
  tmp=$(mktemp -d)
  sed -e "s|@NAME@|$name|" -e "s|@SSH_PUBKEY@|$(cat "$KEY")|" "$CI/node-user-data.tpl" > "$tmp/user-data"
  sed -e "s|@ISOLATED_MAC@|$imac|" -e "s|@INTERNET_MAC@|$emac|" "$CI/node-network-config.tpl" > "$tmp/network-config"
  printf 'instance-id: %s-%s\nlocal-hostname: %s\n' "$name" "$(date +%s)" "$name" > "$tmp/meta-data"
  cloud-localds -N "$tmp/network-config" "$tmp/seed.iso" "$tmp/user-data" "$tmp/meta-data"
  $V vol-create-as "$POOL" "$name-seed.iso" "$(stat -c %s "$tmp/seed.iso")" --format raw
  $V vol-upload --pool "$POOL" "$name-seed.iso" "$tmp/seed.iso"
  rm -rf "$tmp"
}

create() {
  local xml
  xml=$($V net-info "$ISOLATED" 2>/dev/null || true); grep -q 'Active:.*yes' <<<"$xml" || { echo "$ISOLATED is not active (make isolated-network-up)"; exit 1; }
  xml=$($V net-info "$INTERNET" 2>/dev/null || true); grep -q 'Active:.*yes' <<<"$xml" || { echo "$INTERNET is not active (make internet-network-up)"; exit 1; }
  $V vol-info --pool "$POOL" "$TEMPLATE_DISK" >/dev/null || { echo "missing $TEMPLATE_DISK (make template-vm-create)"; exit 1; }
  [ "$($V domstate kg-template-vm)" = "shut off" ] || { echo "kg-template-vm must be shut off"; exit 1; }
  [ -r "$KEY" ] || { echo "public key $KEY not readable"; exit 1; }
  while read -r name role ip imac emac vcpus mem disk; do
    if $V dominfo "$name-vm" >/dev/null 2>&1; then echo "$name-vm already exists; run destroy first"; exit 1; fi
  done < <(rows)
  reserve_addresses
  while read -r name role ip imac emac vcpus mem disk; do
    echo "== creating $name-vm ($role, $ip, ${vcpus} vCPU, ${mem} MiB, ${disk} GiB)"
    $V vol-clone --pool "$POOL" "$TEMPLATE_DISK" "$name-disk.qcow2" >/dev/null
    $V vol-resize --pool "$POOL" "$name-disk.qcow2" "${disk}G"
    make_seed "$name" "$imac" "$emac"
    virt-install --connect qemu:///system --name "$name-vm" --import \
      --memory "$mem" --vcpus "$vcpus" --os-variant ubuntu24.04 \
      --disk "vol=$POOL/$name-disk.qcow2,bus=virtio" \
      --disk "vol=$POOL/$name-seed.iso,device=cdrom" \
      --network "network=$ISOLATED,mac=$imac,model=virtio" \
      --network "network=$INTERNET,mac=$emac,model=virtio" \
      --graphics none --noautoconsole >/dev/null
  done < <(rows)
  while read -r name role ip imac emac vcpus mem disk; do
    if wait_ssh "$ip" 300; then echo "reachable: $name at $ip"; else echo "NOT reachable: $name at $ip"; fi
  done < <(rows)
}

status() {
  printf '%-18s %-10s %-12s %s\n' VM STATE ADDRESS NICS
  while read -r name role ip imac emac vcpus mem disk; do
    local st nics
    st=$($V domstate "$name-vm" 2>/dev/null || echo missing)
    nics=$($V domiflist "$name-vm" 2>/dev/null | awk 'NR>2 && NF {print $3}' | paste -sd, || true)
    printf '%-18s %-10s %-12s %s\n' "$name-vm" "$st" "$ip" "$nics"
  done < <(rows)
}

test_nodes() {
  FAILED=0
  local ids=""
  while read -r name role ip imac emac vcpus mem disk; do
    if ! ssh_node "$ip" true 2>/dev/null; then bad "$name: SSH to $ip fails"; continue; fi
    ok "$name: SSH reachable at $ip"
    [ "$(ssh_node "$ip" hostname)" = "$name" ] && ok "$name: hostname" || bad "$name: hostname"
    [ "$(ssh_node "$ip" nproc)" = "$vcpus" ] && ok "$name: $vcpus vCPUs" || bad "$name: vCPU count"
    local kb; kb=$(ssh_node "$ip" "awk '/MemTotal/ {print \$2}' /proc/meminfo")
    [ "$kb" -ge $(( mem * 900 )) ] && ok "$name: memory about ${mem} MiB" || bad "$name: memory ($kb kB)"
    local gb; gb=$(ssh_node "$ip" "df -BG --output=size / | tail -1 | tr -dc 0-9")
    [ "$gb" -ge $(( disk - 2 )) ] && ok "$name: root disk grown to ${gb} GiB" || bad "$name: root disk is ${gb} GiB"
    ssh_node "$ip" "test -e /sys/kernel/btf/vmlinux" && ok "$name: kernel BTF present" || bad "$name: kernel BTF missing"
    ids="$ids $(ssh_node "$ip" cat /etc/machine-id)"
  done < <(rows)
  [ "$(tr ' ' '\n' <<<"$ids" | grep -c .)" = "$(tr ' ' '\n' <<<"$ids" | grep . | sort -u | wc -l)" ] && ok "machine-ids are unique" || bad "machine-ids are not unique"
  local first; first=$(rows | head -1 | awk '{print $3}')
  while read -r name role ip imac emac vcpus mem disk; do
    [ "$ip" = "$first" ] && continue
    ssh_node "$first" "ping -c2 -W2 $ip" >/dev/null 2>&1 && ok "$first reaches $name ($ip)" || bad "$first cannot reach $name ($ip)"
  done < <(rows)
  return $FAILED
}

isolate() {
  while read -r name role ip imac emac vcpus mem disk; do
    $V detach-interface "$name-vm" network --mac "$emac" --live --config
  done < <(rows)
  sleep 5
  local a b
  a=$(rows | sed -n 1p | awk '{print $3}'); b=$(rows | sed -n 2p | awk '{print $3}')
  KG_LAB_KEY="$KEY" "$HERE/test-isolation.sh" "$a" "$b" ubuntu
}

snapshot() {
  while read -r name role ip imac emac vcpus mem disk; do $V shutdown "$name-vm" >/dev/null; done < <(rows)
  while read -r name role ip imac emac vcpus mem disk; do
    wait_off "$name-vm" || { echo "$name-vm did not shut down"; exit 1; }
    $V snapshot-create-as "$name-vm" "$name-clean-snapshot" "clean node after creation"
  done < <(rows)
  while read -r name role ip imac emac vcpus mem disk; do $V start "$name-vm" >/dev/null; done < <(rows)
  while read -r name role ip imac emac vcpus mem disk; do wait_ssh "$ip" 300 && echo "back up: $name" || echo "NOT reachable: $name"; done < <(rows)
}

destroy() {
  while read -r name role ip imac emac vcpus mem disk; do
    $V destroy "$name-vm" 2>/dev/null || true
    $V undefine "$name-vm" --snapshots-metadata --remove-all-storage 2>/dev/null || true
    $V vol-delete --pool "$POOL" "$name-seed.iso" 2>/dev/null || true
    $V vol-delete --pool "$POOL" "$name-disk.qcow2" 2>/dev/null || true
  done < <(rows)
}

case "${1:-}" in
  create) create ;; status) status ;; test) test_nodes ;; isolate) isolate ;;
  snapshot) snapshot ;; destroy) destroy ;;
  *) echo "usage: $0 create|status|test|isolate|snapshot|destroy"; exit 2 ;;
esac
