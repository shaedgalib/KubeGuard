#!/usr/bin/env bash
# P2-U7: Kyverno outage drill. Kyverno behaves differently when it stops cleanly and when it crashes:
#   clean stop (scale to zero)  Kyverno removes its webhook configurations, so its policies do not apply until it
#                               is running again; Pod Security Admission keeps working on its own.
#   crash (pod killed)          the webhook configuration stays and fails closed: pod creation in workload
#                               namespaces is refused until the replacement is ready.
# The drill shows both, shows that system namespaces are never affected, that deleting the webhook configuration
# unblocks a stuck cluster, and that Kyverno brings the webhook and the policies back by itself.
# Usage: kyverno.sh drill        (about two minutes; always scales the admission controller back up at the end)
set -uo pipefail
cd "$(dirname "$0")/../.."
KC=${PROJECT_KUBECONFIG:-$HOME/.kube/kubeguard.kubeconfig}
k() { env -u KUBECONFIG kubectl --kubeconfig "$KC" "$@"; }
FAILED=0
ok()   { echo "PASS  $*"; }
bad()  { echo "FAIL  $*"; FAILED=1; }
info() { echo "INFO  $*"; }
WH=kyverno-resource-validating-webhook-cfg
DEP=kyverno-admission-controller
LABEL=app.kubernetes.io/component=admission-controller
NS=kyverno-drill   # a workload namespace without Pod Security labels, so that only Kyverno can refuse

restore() { k -n kyverno scale deployment/$DEP --replicas=1 >/dev/null 2>&1; k delete namespace $NS --ignore-not-found --wait=false >/dev/null 2>&1; }
trap restore EXIT

pod() {  # a compliant pod (limits, allowed registry); a second argument "priv" makes it privileged
  printf 'apiVersion: v1\nkind: Pod\nmetadata: {name: %s}\nspec:\n  containers:\n    - name: c\n      image: docker.io/library/busybox:1.37\n      command: [sleep, "1"]\n      resources: {limits: {cpu: 50m, memory: 32Mi}}\n' "$1"
  [ "${2:-}" = priv ] && printf '      securityContext: {privileged: true}\n'
  return 0
}
dry() { k -n "$1" apply --dry-run=server -f - 2>&1; }
accepted() { grep -q 'server dry run' <<<"$1" && ! grep -qiE 'error|denied|forbidden' <<<"$1"; }
wait_for() {  # wait_for <seconds> <command...>
  local end=$(( SECONDS + $1 )); shift
  while [ $SECONDS -lt $end ]; do "$@" >/dev/null 2>&1 && return 0; sleep 2; done; return 1
}
webhook_there()      { k get validatingwebhookconfiguration $WH; }
kyverno_webhooks()   { k get validatingwebhookconfiguration,mutatingwebhookconfiguration --no-headers 2>/dev/null | grep -c kyverno; }
denies_privileged()  { grep -q 'disallow-privileged-containers' <<<"$(pod outage-priv priv | dry $NS)"; }
no_admission_pods()  { [ -z "$(k -n kyverno get pods -l $LABEL --no-headers 2>/dev/null)" ]; }
ready_again()        { k -n kyverno rollout status deployment/$DEP --timeout=180s >/dev/null 2>&1; }

recover() {  # wait until Kyverno is back with its webhook and its policies; arg: start time in $SECONDS
  ready_again && ok "the admission controller is ready again after $(( SECONDS - $1 )) s" || bad "the admission controller did not become ready in 180 s"
  wait_for 120 webhook_there && ok "Kyverno recreated the webhook configuration by itself ($(( SECONDS - $1 )) s after the start)" \
    || bad "the webhook configuration did not come back; restart the admission controller (kubectl -n kyverno rollout restart deployment/$DEP)"
  wait_for 120 denies_privileged && ok "the policies refuse a privileged pod again ($(( SECONDS - $1 )) s after the start)" \
    || bad "the policies do not refuse a privileged pod after the restart"
}

drill() {
  k get deployment -n kyverno $DEP >/dev/null 2>&1 || { echo "Kyverno is not installed (make kyverno-install)"; exit 1; }
  k create namespace $NS >/dev/null 2>&1 || true
  local out t0 n

  echo "== 1. normal operation"
  denies_privileged && ok "a privileged pod is refused by Kyverno in $NS" || bad "a privileged pod is not refused before the drill starts"

  echo "== 2. clean stop: scale the admission controller to zero"
  k -n kyverno scale deployment/$DEP --replicas=0 >/dev/null
  wait_for 90 no_admission_pods && ok "the admission controller pod is gone" || bad "the admission controller pod is still there"
  sleep 5
  n=$(kyverno_webhooks)
  [ "$n" = 0 ] && ok "Kyverno removed its webhook configurations when it stopped" || bad "$n Kyverno webhook configurations are still registered (the behaviour changed: read the runbook)"
  out=$(pod outage-priv priv | dry $NS)
  accepted "$out" && info "a privileged pod IS accepted in $NS while Kyverno is stopped: the policies do not apply until it runs again" \
    || info "a privileged pod was still refused in $NS: ${out:0:140}"
  out=$(pod outage-priv priv | dry sample)
  grep -q 'violates PodSecurity "restricted' <<<"$out" && ok "Pod Security Admission still refuses a privileged pod in the restricted namespace sample" || bad "no refusal by Pod Security Admission in sample: ${out:0:140}"
  out=$(pod outage-sys | dry monitoring)
  accepted "$out" && ok "the system namespace monitoring is not affected" || bad "monitoring was refused: ${out:0:140}"
  t0=$SECONDS
  k -n kyverno scale deployment/$DEP --replicas=1 >/dev/null
  recover $t0

  echo "== 3. crash: kill the admission controller pod without a clean shutdown"
  local victim; victim=$(k -n kyverno get pods -l $LABEL -o name | head -1)
  t0=$SECONDS
  k -n kyverno delete "$victim" --force --grace-period=0 >/dev/null 2>&1
  n=0; out=""
  for _ in $(seq 1 30); do
    out=$(pod crash-probe | dry $NS)
    accepted "$out" || { n=1; break; }
    sleep 1
  done
  [ $n = 1 ] && ok "a compliant pod in $NS is refused while the webhook has no backend (fails closed): $(grep -o 'failed calling webhook[^:]*' <<<"$out" | head -1)" \
    || bad "no refusal was seen during the crash"
  out=$(pod outage-sys | dry monitoring)
  accepted "$out" && ok "the system namespace monitoring is not affected by the crash" || bad "monitoring was refused during the crash: ${out:0:140}"
  if k delete validatingwebhookconfiguration $WH >/dev/null 2>&1; then
    out=$(pod crash-probe | dry $NS)
    accepted "$out" && ok "deleting the webhook configuration unblocks $NS" || info "still refused after deleting the webhook: ${out:0:140}"
  else
    info "the webhook configuration was already gone"
  fi
  recover $t0
  exit $FAILED
}

case "${1:-}" in drill) drill ;; *) echo "usage: $0 drill"; exit 2 ;; esac
