#!/usr/bin/env bash
# P0-U5 acceptance test for the kg-isolated-network.
# Usage: test-isolation.sh                      static checks only (no VMs needed)
#        test-isolation.sh <vmA-ip> <vmB-ip> <ssh-user>   adds in-VM checks
set -u
NET=kg-isolated-network
V="virsh -c qemu:///system"
fail=0
ok()   { echo "PASS  $*"; }
bad()  { echo "FAIL  $*"; fail=1; }

# --- static checks (host side) ---
$V net-info "$NET" 2>/dev/null | grep -q 'Active:.*yes' && ok "network $NET is active" || bad "network $NET not active"
$V net-dumpxml "$NET" | grep -q '<forward' && bad "network has a <forward> element (not isolated)" || ok "no <forward> element"
$V net-dumpxml "$NET" | grep -q "address='10.77.0.1'" && ok "subnet is 10.77.0.0/24" || bad "unexpected subnet"
if sudo nft list ruleset 2>/dev/null | grep -q 'kg-isolated-br.*masquerade\|masquerade.*10\.77\.0'; then
  bad "masquerade rule exists for 10.77.0.0/24"
else
  ok "no NAT/masquerade rule for the lab subnet"
fi

# --- in-VM checks ---
if [ $# -eq 3 ]; then
  A=$1; B=$2; U=$3
  GW=$(ip route | awk '/^default/ {print $3; exit}')
  SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new $U@$A"
  $SSH "ping -c2 -W2 $B" >/dev/null 2>&1 && ok "VM A reaches VM B" || bad "VM A cannot reach VM B"
  $SSH "ping -c2 -W2 $GW" >/dev/null 2>&1 && bad "VM A reaches the LAN gateway $GW" || ok "VM A cannot reach LAN gateway $GW"
  $SSH "ping -c2 -W2 1.1.1.1" >/dev/null 2>&1 && bad "VM A reaches the internet" || ok "VM A cannot reach the internet"
else
  echo "SKIP  in-VM checks (pass <vmA-ip> <vmB-ip> <ssh-user> once VMs exist, P0-U6)"
fi
exit $fail
