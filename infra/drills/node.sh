#!/usr/bin/env bash
# P1-U10: node drills on a worker: drain, failure and rejoin.
# Usage: node.sh drain <node> | fail <node> | rejoin <node>      (node = kg-worker-1 or kg-worker-2)
# Only workers are allowed: the control plane has one etcd member (see the etcd runbook).
# Each drill prints PASS/FAIL lines and the elapsed times it measured itself.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
CONF=${NODES_CONF:-$HERE/../libvirt/nodes.conf}
KC=${PROJECT_KUBECONFIG:-$HOME/.kube/kubeguard.kubeconfig}
KEY=${KG_LAB_KEY:-$HOME/.ssh/kubeguard-lab}
V="virsh -c qemu:///system"
FAILED=0

k()    { env -u KUBECONFIG kubectl --kubeconfig "$KC" "$@"; }
rows() { grep -v '^[[:space:]]*#' "$CONF" | grep -v '^[[:space:]]*$'; }
ip_of()   { rows | awk -v n="$1" '$1==n {print $3}'; }
role_of() { rows | awk -v n="$1" '$1==n {print $2}'; }
ssh_n() {  # ssh_n <node-ip> <command...>
  ssh -n -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ubuntu@"$1" "${@:2}"
}
ok()   { echo "PASS  $*"; }
bad()  { echo "FAIL  $*"; FAILED=1; }
info() { echo "INFO  $*"; }

wait_until() {  # wait_until <seconds> <command...>
  local end=$(( SECONDS + $1 )); shift
  while [ "$SECONDS" -lt "$end" ]; do "$@" >/dev/null 2>&1 && return 0; sleep 5; done
  return 1
}
api_ok()        { k get --raw /readyz >/dev/null 2>&1; }
node_ready()    { [ "$(k get node "$1" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = True ]; }
node_notready() { api_ok && ! node_ready "$1"; }
node_gone()     { api_ok && ! k get node "$1" >/dev/null 2>&1; }
ssh_up()        { ssh_n "$(ip_of "$1")" true; }
ssh_down()      { ! ssh_up "$1"; }
deployments_ok() { api_ok && [ -z "$(k get deployments -A --no-headers 2>/dev/null | awk '{split($3,a,"/"); if (a[1]!=a[2]) print}')" ]; }
cilium_ready()  { [ "$(k -n kube-system get pods -l k8s-app=cilium --field-selector "spec.nodeName=$1" -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)" = true ]; }
pods_ok()       { api_ok && [ -z "$(k get pods -A --no-headers 2>/dev/null | awk '$4!="Running" && $4!="Completed"')" ]; }

pods_on_node() {  # workload pods (not DaemonSet pods) on a node, as namespace/name
  k get pods -A --field-selector "spec.nodeName=$1" -o json | python3 -c '
import sys, json
for p in json.load(sys.stdin)["items"]:
    if any(o.get("kind") == "DaemonSet" for o in p["metadata"].get("ownerReferences", [])): continue
    print(p["metadata"]["namespace"] + "/" + p["metadata"]["name"])'
}
not_running() { k get pods -A --no-headers 2>/dev/null | awk '$4!="Running" && $4!="Completed" {print "  " $1 "/" $2 " " $4}'; }

precheck() {
  [ -n "$(ip_of "$NODE")" ] || { echo "unknown node: $NODE"; exit 2; }
  [ "$(role_of "$NODE")" = worker ] || { echo "$NODE is not a worker; refusing"; exit 2; }
  api_ok || { echo "API not ready"; exit 1; }
  node_ready "$NODE" || { echo "$NODE is not Ready before the drill"; exit 1; }
  pods_ok || { echo "some pods are not Running before the drill:"; not_running; exit 1; }
}

drain_node() {
  echo "workload pods on $NODE before:"; pods_on_node "$NODE" | sed 's/^/  /'
  k cordon "$NODE" >/dev/null && ok "$NODE cordoned (no new pods)"
  if k drain "$NODE" --ignore-daemonsets --delete-emptydir-data --timeout=180s >/dev/null 2>&1; then ok "drain finished"; else bad "drain did not finish in 180 s"; fi
  local left; left=$(pods_on_node "$NODE" | wc -l)
  [ "$left" = 0 ] && ok "no workload pods left on $NODE" || { bad "$left workload pod(s) still on $NODE"; pods_on_node "$NODE" | sed 's/^/  /'; }
  sleep 20
  echo "pods not Running while $NODE is drained:"; not_running
  info "pods that use a local-path volume stay Pending while their node is drained: the volume lives on that node only"
}

drill_drain() {
  precheck
  local t0=$SECONDS
  drain_node
  echo "== uncordon $NODE"
  k uncordon "$NODE" >/dev/null && ok "$NODE schedulable again"
  wait_until 300 pods_ok && ok "all pods Running again after $(( SECONDS - t0 )) s in total" || { bad "pods not all Running within 300 s:"; not_running; }
  node_ready "$NODE" && ok "$NODE Ready" || bad "$NODE not Ready"
}

drill_fail() {
  precheck
  echo "workload pods on $NODE before:"; pods_on_node "$NODE" | sed 's/^/  /'
  local t0=$SECONDS
  echo "== power off $NODE-vm (hard stop, like a crash)"
  $V destroy "$NODE-vm" >/dev/null
  wait_until 240 node_notready "$NODE" && ok "node reported NotReady after $(( SECONDS - t0 )) s" || bad "node still Ready after 240 s"
  echo "== wait for the cluster to move the pods (the default eviction delay is 5 minutes)"
  local t1=$SECONDS
  wait_until 720 deployments_ok && ok "all Deployments fully available again $(( SECONDS - t0 )) s after the power-off" || bad "Deployments not available within 720 s"
  info "eviction and rescheduling took $(( SECONDS - t1 )) s after the node was reported NotReady"
  echo "pods not Running while $NODE is down:"; not_running
  info "a pod that uses a local-path volume on $NODE (if one runs there) cannot move: the volume lives on that node only"
  echo "== power on $NODE-vm"
  local t2=$SECONDS
  $V start "$NODE-vm" >/dev/null
  wait_until 300 ssh_up "$NODE" && ok "node reachable over SSH after $(( SECONDS - t2 )) s" || bad "node not reachable"
  wait_until 300 node_ready "$NODE" && ok "node Ready again after $(( SECONDS - t2 )) s" || bad "node not Ready within 300 s"
  wait_until 300 pods_ok && ok "all pods Running again after $(( SECONDS - t2 )) s" || { bad "pods not all Running:"; not_running; }
  info "total drill time $(( SECONDS - t0 )) s"
}

drill_rejoin() {
  precheck
  local ip cp t0=$SECONDS; ip=$(ip_of "$NODE"); cp=$(rows | awk '$2=="control" {print $3; exit}')
  drain_node
  echo "== remove the node from the cluster"
  k delete node "$NODE" >/dev/null && wait_until 60 node_gone "$NODE" && ok "node object deleted" || bad "node object not deleted"
  echo "== reset the node and reboot it (clean network state)"
  ssh_n "$ip" 'sudo kubeadm reset -f >/dev/null 2>&1; sudo rm -rf /etc/cni/net.d; sudo systemctl reboot' >/dev/null 2>&1 || true
  wait_until 60 ssh_down "$NODE" || true
  wait_until 300 ssh_up "$NODE" && ok "node back after the reboot" || { bad "node did not come back"; exit 1; }
  echo "== join again with a new short-lived token"
  local join
  join=$(ssh_n "$cp" 'sudo kubeadm token create --ttl 15m --print-join-command' 2>/dev/null)
  [ -n "$join" ] || { bad "could not create a join command"; exit 1; }
  if ssh_n "$ip" "sudo $join --node-name $NODE --cri-socket unix:///run/containerd/containerd.sock" >/dev/null 2>&1; then ok "kubeadm join finished"; else bad "kubeadm join failed"; fi
  local tj=$SECONDS
  wait_until 300 node_ready "$NODE" && ok "node Ready $(( SECONDS - tj )) s after the join" || bad "node not Ready within 300 s"
  wait_until 600 cilium_ready "$NODE" && ok "Cilium agent on $NODE ready $(( SECONDS - tj )) s after the join" || bad "Cilium agent on $NODE not ready within 600 s"
  k uncordon "$NODE" >/dev/null 2>&1 || true
  local addr; addr=$(k get node "$NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
  [ "$addr" = "$ip" ] && ok "node address is $addr (isolated network)" || bad "node address is '$addr', expected $ip"
  wait_until 600 pods_ok && ok "all pods Running again $(( SECONDS - tj )) s after the join ($(( SECONDS - t0 )) s in total)" || { bad "pods not all Running within 600 s:"; not_running; }
}

NODE=${2:-}
case "${1:-}" in
  drain)  drill_drain ;;
  fail)   drill_fail ;;
  rejoin) drill_rejoin ;;
  *) echo "usage: $0 drain|fail|rejoin <node>"; exit 2 ;;
esac
exit $FAILED
