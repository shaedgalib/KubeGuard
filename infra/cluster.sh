#!/usr/bin/env bash
# P1-U11 / P1-U13: lab lifecycle in one command, with timed stages.
# Usage: cluster.sh up | down | reset | cluster | rebuild
#   up       start the networks and the node VMs, wait until the API answers and all nodes are Ready
#   down     shut the node VMs down gracefully (frees their RAM; networks and disks stay)
#   reset    DESTROY the node VMs and create fresh ones from kg-template-vm (needs CONFIRM=yes)
#   cluster  from clean VMs to the full cluster: Kubernetes, Cilium, load balancer, Gateway API,
#            storage, monitoring, Kyverno and its policies, sample app, Pod Security labels, the acceptance
#            checks of U5 to U8 and the hardening
#            tests of Phase 2 (the hardening itself is part of the Ansible stage)
#   rebuild  reset + cluster, and the total time against the 40 minute target (needs CONFIRM=yes)
# Every stage prints its own duration; the log is kept outside the repository.
set -uo pipefail
cd "$(dirname "$0")/.."
V="virsh -c qemu:///system"
KC=${PROJECT_KUBECONFIG:-$HOME/.kube/kubeguard.kubeconfig}
CONF=${NODES_CONF:-infra/libvirt/nodes.conf}
LOG_DIR=${KG_LOG_DIR:-$HOME/.local/share/kubeguard/rebuild-logs}
TARGET_SECONDS=2400        # the P1-U13 target: under 40 minutes
GRAFANA_PW_FILE=$HOME/.config/kubeguard/grafana-admin-password

k()     { env -u KUBECONFIG kubectl --kubeconfig "$KC" "$@"; }
rows()  { grep -v '^[[:space:]]*#' "$CONF" | grep -v '^[[:space:]]*$'; }
names() { rows | awk '{print $1}'; }

STAGES=()      # "name seconds status"
stage() {      # stage <name> <command...>   runs the command, records its duration, stops the run on failure
  local name=$1 t0=$SECONDS rc; shift
  echo; echo "=== $name"
  "$@"; rc=$?
  local d=$(( SECONDS - t0 ))
  STAGES+=("$name|$d|$([ $rc = 0 ] && echo ok || echo FAILED)")
  echo "--- $name: $d s ($([ $rc = 0 ] && echo ok || echo "FAILED, exit $rc"))"
  [ $rc = 0 ] || { summary; echo "stopped at stage: $name"; exit $rc; }
}
summary() {
  echo; echo "=== stage times"
  local total=0 s
  for s in "${STAGES[@]}"; do IFS='|' read -r n d st <<<"$s"; printf '%6s s  %-8s %s\n' "$d" "$st" "$n"; total=$(( total + d )); done
  printf '%6s s  total\n' "$total"
}

net_ensure() {  # net_ensure <network> <make target that defines it>
  local info
  if ! info=$($V net-info "$1" 2>/dev/null); then make "$2"; return; fi
  [[ $info =~ Active:[[:space:]]+yes ]] || $V net-start "$1"
}
networks()   { net_ensure kg-isolated-network isolated-network-up && net_ensure kg-internet-access-network internet-network-up; }
vms_exist()  { $V dominfo "$(names | head -1)-vm" >/dev/null 2>&1; }
start_vms()  { local n; for n in $(names); do [ "$($V domstate "$n-vm")" = running ] || $V start "$n-vm" >/dev/null; done; }
api_ok()     { k get --raw /readyz >/dev/null 2>&1; }
ready_nodes(){ k get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l; }
want_nodes() { rows | wc -l; }
wait_for()   { local end=$(( SECONDS + $1 )) ; shift; while [ $SECONDS -lt $end ]; do "$@" >/dev/null 2>&1 && return 0; sleep 5; done; return 1; }
nodes_all_ready() { api_ok && [ "$(ready_nodes)" = "$(want_nodes)" ]; }
wait_nodes_ready() { wait_for 600 nodes_all_ready && k get nodes; }

do_up() {
  stage "networks"        networks
  vms_exist || { echo "no node VMs: run 'make reset CONFIRM=yes' or 'make cluster'"; return 1; }
  stage "start the VMs"   start_vms
  stage "API and nodes Ready" wait_nodes_ready
  summary
}

vms_down() {
  local n; for n in $(names | tac); do $V shutdown "$n-vm" >/dev/null 2>&1 || true; done
  for n in $(names); do
    for _ in $(seq 1 90); do [ "$($V domstate "$n-vm")" = "shut off" ] && break; sleep 2; done
    [ "$($V domstate "$n-vm")" = "shut off" ] || { echo "$n-vm did not shut down"; return 1; }
  done
}
do_down() { stage "shut the VMs down" vms_down; summary; }

need_confirm() {
  [ "${CONFIRM:-}" = yes ] && return 0
  echo "This DESTROYS the node VMs (kg-control-1, kg-worker-1, kg-worker-2) and everything on them."
  echo "Run again with CONFIRM=yes to continue, for example: make reset CONFIRM=yes"
  return 1
}
do_reset() {
  need_confirm || exit 2
  $V dominfo kg-template-vm >/dev/null 2>&1 || { echo "kg-template-vm is missing: build it first (make template-vm-create)"; exit 1; }
  stage "networks"            networks
  stage "destroy the node VMs" make vms-destroy
  stage "create clean node VMs" make vms
}

save_grafana_password() {
  local pw; pw=$(k -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d) || return 1
  mkdir -p "$(dirname "$GRAFANA_PW_FILE")"; chmod 700 "$(dirname "$GRAFANA_PW_FILE")"
  ( umask 077; printf '%s\n' "$pw" > "$GRAFANA_PW_FILE" ); echo "Grafana password saved to $GRAFANA_PW_FILE"
}
check_lb_and_gateway() {
  local lb gw i
  for i in $(seq 1 24); do
    lb=$(k get svc lb-test -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    gw=$(k get gateway gw-test -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
    [ -n "$lb" ] && [ -n "$gw" ] && break; sleep 5
  done
  echo "LoadBalancer $lb, Gateway $gw"
  local ok=1
  for a in "$lb" "$gw"; do
    [ -n "$a" ] || { echo "FAIL  no address"; ok=0; continue; }
    for i in $(seq 1 24); do [ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$a/")" = 200 ] && break; sleep 5; done
    [ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$a/")" = 200 ] && echo "PASS  http://$a/ answers 200" || { echo "FAIL  http://$a/"; ok=0; }
  done
  k delete -f k8s/tests/ >/dev/null 2>&1
  [ $ok = 1 ]
}

do_cluster() {
  stage "networks"                networks
  vms_exist || { echo "no node VMs: run 'make reset CONFIRM=yes' first"; exit 1; }
  stage "start the VMs"           start_vms
  stage "internet window (images and packages)" infra/libvirt/build-nodes.sh attach
  [ -x .venv/bin/ansible-playbook ] || stage "install Ansible (.venv)" make ansible-setup
  stage "Kubernetes (Ansible: common, containerd, packages, kubeadm init and join)" make ansible-apply
  stage "Gateway API CRDs"        make gateway-api-crds
  stage "Cilium and Hubble"       make cilium-install
  stage "nodes Ready"             wait_nodes_ready
  stage "load balancer pool and L2 policy" make cilium-lb
  stage "storage (local-path)"    make storage-install
  stage "Grafana admin Secret"    make monitoring-secret
  stage "monitoring (Prometheus, Grafana)" make monitoring-install
  stage "save the Grafana password locally" save_grafana_password
  stage "Kyverno (policy engine)" make kyverno-install
  stage "Kyverno policies"        make kyverno-policies
  stage "sample app"              make sample-app-install
  stage "Pod Security labels and default service accounts" make access-apply
  stage "check: Cilium status"    make cilium-status
  stage "check: storage, load balancer, Gateway (U6)" make net-test-u6
  stage "check: load balancer and Gateway answer from the host" check_lb_and_gateway
  stage "check: monitoring (U7)"  make net-test-u7
  stage "check: sample app and Hubble flows (U8)" make net-test-u8
  stage "check: hardening (P2)"   make test-hardening
  summary
}

do_rebuild() {
  need_confirm || exit 2
  local t0=$SECONDS
  do_reset
  do_cluster
  local total=$(( SECONDS - t0 ))
  echo; echo "rebuild total: $total s ($(( total / 60 )) min $(( total % 60 )) s); target $TARGET_SECONDS s (40 min)"
  [ "$total" -le "$TARGET_SECONDS" ] && echo "PASS  within the 40 minute target" || echo "FAIL  above the 40 minute target"
}

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/${1:-none}-$(date +%Y%m%d-%H%M%S).log"
case "${1:-}" in
  up|down|reset|cluster|rebuild) echo "log: $LOG"; { "do_$1"; } 2>&1 | tee "$LOG"; exit "${PIPESTATUS[0]}" ;;
  *) echo "usage: $0 up|down|reset|cluster|rebuild"; exit 2 ;;
esac
