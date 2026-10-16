#!/usr/bin/env bash
# P2-U4 and P2-U7: evidence for Pod Security Admission and the Kyverno policies, as the cluster shows it.
# Usage: evidence-access.sh     (the output is pasted unchanged into docs/reports/P2-U4-U7-admission-evidence.md)
# It only reads, except for one temporary namespace in which the refusal messages are produced with server-side
# dry runs (nothing is created in it); the namespace is deleted when the script ends.
set -uo pipefail
cd "$(dirname "$0")/../.."

KC=${PROJECT_KUBECONFIG:-$HOME/.kube/kubeguard.kubeconfig}
KEY=${KG_LAB_KEY:-$HOME/.ssh/kubeguard-lab}
CONF=${NODES_CONF:-infra/libvirt/nodes.conf}
k() { env -u KUBECONFIG kubectl --kubeconfig "$KC" "$@"; }
NS=hardening-policy-evidence
trap 'k delete namespace $NS --ignore-not-found --wait=false >/dev/null 2>&1' EXIT

echo "== date: $(date -Is)"
echo
echo "== Pod Security labels compared with k8s/access/pod-security.conf"
infra/access/pod-security.sh check
echo
echo "== What the restricted level would flag in running pods, per namespace (server-side dry run, nothing changed)"
k label --dry-run=server --overwrite namespaces --all pod-security.kubernetes.io/enforce=restricted 2>&1 | grep -E '^Warning' | sed 's/^Warning: //'
echo
echo "== Kyverno release, pods and their resources"
env -u KUBECONFIG helm --kubeconfig "$KC" -n kyverno list 2>&1
k -n kyverno get pods -o json | jq -r '.items[] | .metadata.name as $n | .spec.containers[] | [$n, .name, (.resources.requests.cpu // "-"), (.resources.requests.memory // "-"), (.resources.limits.memory // "-")] | @tsv' | column -t -s $'\t' -N POD,CONTAINER,CPU_REQ,MEM_REQ,MEM_LIMIT
echo
echo "== Kyverno policies"
k get validatingpolicies.policies.kyverno.io 2>&1
echo
echo "== The policy webhook: failure policy, timeout and the namespaces it is not called for"
k get validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg -o json | jq -c '.webhooks[] | {name, failurePolicy, timeoutSeconds, not_called_for: ((.namespaceSelector.matchExpressions // [])[0].values // null)}'
echo
echo "== Refusals and acceptances (server-side dry runs in the temporary namespace $NS)"
k create namespace $NS >/dev/null 2>&1
pod() {  # pod <name> <image> <privileged> <limits>
  printf 'apiVersion: v1\nkind: Pod\nmetadata: {name: %s}\nspec:\n  containers:\n    - name: c\n      image: %s\n      command: [sleep, "1"]\n' "$1" "$2"
  [ "$3" = true ] && printf '      securityContext: {privileged: true}\n'
  [ "$4" = true ] && printf '      resources: {limits: {cpu: 50m, memory: 32Mi}}\n'
}
show() { echo "-- $1"; k -n "$2" apply --dry-run=server -f - 2>&1 | sed 's/^Error from server: error when creating "STDIN": //'; }
pod demo-privileged docker.io/library/busybox:1.37 true true  | show "privileged container, in $NS" $NS
pod demo-nolimits   docker.io/library/busybox:1.37 false false | show "no limits, in $NS" $NS
pod demo-registry   evil.example.com/app:1 false true         | show "image from evil.example.com, in $NS" $NS
pod demo-ok         docker.io/library/busybox:1.37 false true  | show "compliant pod, in $NS" $NS
pod demo-privileged docker.io/library/busybox:1.37 true true  | show "the same privileged pod in sample (Pod Security restricted answers first)" sample
pod demo-nolimits   docker.io/library/busybox:1.37 false false | show "the same pod without limits in monitoring (outside the policies)" monitoring
echo
echo "== Free memory on the nodes (free -m, available column)"
grep -v '^[[:space:]]*#' "$CONF" | grep -v '^[[:space:]]*$' | while read -r name role ip _; do
  printf '%s: ' "$name"
  ssh -n -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ubuntu@"$ip" "free -m | awk 'NR==2{print \"total \" \$2 \" MB, available \" \$7 \" MB\"}'"
done
