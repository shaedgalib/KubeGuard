#!/usr/bin/env bash
# P2-U5: apply, remove and try out the network policies in k8s/policies/ (one file per namespace).
# Usage: policies.sh apply  [namespace...]     create or update the CiliumNetworkPolicies
#        policies.sh remove [namespace...]     delete them (the namespace is open again)
#        policies.sh audit on|off [namespace...]   switch policy audit mode for the pods that run now
#        policies.sh status                    policies, enforcement and audit mode per pod
# Without namespaces every file in k8s/policies/ is used. Project kubeconfig only.
#
# Audit mode is a per-endpoint option of Cilium: while it is on, traffic that a policy would drop is allowed and
# shown in Hubble with the verdict AUDIT. It belongs to the running pod: a pod that is created later (a rollout, a
# restart) starts with audit mode off, so run "audit on" again after one. Turn it on before "apply", look at the
# AUDIT flows (make flows), fix the policies, then turn it off to enforce.
set -uo pipefail
cd "$(dirname "$0")/../.."
KC=${PROJECT_KUBECONFIG:-$HOME/.kube/kubeguard.kubeconfig}
DIR=${POLICY_DIR:-k8s/policies}
k() { env -u KUBECONFIG kubectl --kubeconfig "$KC" "$@"; }
agents() { k -n kube-system get pods -l k8s-app=cilium -o name; }
dbg() { local a=$1; shift; k -n kube-system exec "$a" -c cilium-agent -- cilium-dbg "$@"; }

namespaces() {  # namespaces() <args...>: the arguments, or every file in the policy directory
  if [ $# -gt 0 ]; then printf '%s\n' "$@"; else for f in "$DIR"/*.yaml; do basename "$f" .yaml; done; fi
}
check_ns() { [ -f "$DIR/$1.yaml" ] || { echo "no policy file $DIR/$1.yaml"; exit 2; }; }

apply() {
  local ns rc=0
  for ns in $(namespaces "$@"); do
    check_ns "$ns"
    k get namespace "$ns" >/dev/null 2>&1 || { echo "skip   $ns (the namespace does not exist)"; continue; }
    k apply -f "$DIR/$ns.yaml" || rc=1
  done
  return $rc
}

remove() {
  local ns rc=0
  for ns in $(namespaces "$@"); do
    check_ns "$ns"
    k get namespace "$ns" >/dev/null 2>&1 || { echo "skip   $ns (the namespace does not exist)"; continue; }
    k delete -f "$DIR/$ns.yaml" --ignore-not-found || rc=1
  done
  return $rc
}

audit() {  # audit on|off [namespace...]
  local mode=$1 value n=0 a id ns; shift
  case $mode in on) value=Enabled ;; off) value=Disabled ;; *) echo "usage: $0 audit on|off [namespace...]"; exit 2 ;; esac
  local want; want=$(namespaces "$@" | paste -sd'|')
  for a in $(agents); do
    while read -r id ns; do
      [[ $ns =~ ^($want)$ ]] || continue
      dbg "$a" endpoint config "$id" PolicyAuditMode=$value >/dev/null 2>&1 && n=$((n + 1)) || echo "warning: $a endpoint $id: could not set PolicyAuditMode=$value"
    done < <(dbg "$a" endpoint list -o json 2>/dev/null | jq -r '.[] | [.id, ((.status.identity.labels // []) | map(select(startswith("k8s:io.kubernetes.pod.namespace="))) | (.[0] // "") | sub("k8s:io.kubernetes.pod.namespace="; ""))] | @tsv')
  done
  echo "PolicyAuditMode=$value on $n endpoints"
}

status() {
  echo "== policies"
  k get ciliumnetworkpolicies -A --no-headers 2>/dev/null | awk '{print $1}' | sort | uniq -c | awk '{print "  " $2 ": " $1 " policies"}'
  echo "== pods: enforcement and audit mode (from the Cilium agents)"
  printf '%-22s %-26s %-8s %s\n' NAMESPACE APP ENFORCED AUDIT-MODE
  local a
  for a in $(agents); do
    dbg "$a" endpoint list -o json 2>/dev/null | jq -r '.[] | select((.status.identity.labels // []) | any(startswith("k8s:io.kubernetes.pod.namespace="))) | [((.status.identity.labels | map(select(startswith("k8s:io.kubernetes.pod.namespace="))) | .[0]) | sub("k8s:io.kubernetes.pod.namespace="; "")), ((.status.identity.labels | map(select(test("^k8s:(app|app.kubernetes.io/name|k8s-app)="))) | .[0] // "-") | sub("^k8s:[^=]*="; "")), (.status.policy.realized["policy-enabled"] // "-"), (.spec.options.PolicyAuditMode // "-")] | @tsv'
  done | sort | awk -F'\t' '{printf "%-22s %-26s %-8s %s\n", $1, $2, $3, $4}'
}

case "${1:-}" in
  apply)  shift; apply "$@" ;;
  remove) shift; remove "$@" ;;
  audit)  shift; audit "$@" ;;
  status) status ;;
  *) echo "usage: $0 apply|remove [namespace...] | audit on|off [namespace...] | status"; exit 2 ;;
esac
