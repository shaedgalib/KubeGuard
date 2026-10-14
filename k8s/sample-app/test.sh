#!/usr/bin/env bash
# P1-U8 acceptance: a request from the host reaches the frontend and the backend through the
# Gateway, and Hubble shows the flows. Uses the project kubeconfig only.
set -uo pipefail
KC="${PROJECT_KUBECONFIG:-$HOME/.kube/kubeguard.kubeconfig}"
k() { env -u KUBECONFIG kubectl --kubeconfig "$KC" "$@"; }
fail=0
check() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (got '$2', want '$3')"; fail=1; fi; }

addr=$(k -n sample get gateway sample-gw -o jsonpath='{.status.addresses[0].value}')
echo "Gateway address: ${addr:-none}"
[ -n "$addr" ] || { echo "FAIL  gateway has no address"; exit 1; }

# Envoy learns new endpoints a few seconds after the pods are ready: retry for up to 60 s.
get() {
  local out="" i
  for i in $(seq 1 30); do
    out=$(curl -s -m 5 "http://$addr$1")
    [ "$out" = "$2" ] && break
    sleep 2
  done
  echo "$out"
}
check "GET /     -> frontend" "$(get / "frontend ok")" "frontend ok"
check "GET /api  -> backend"  "$(get /api "backend ok")" "backend ok"

echo
echo "Hubble flows in namespace sample (last 15 per node, verdicts):"
for p in $(k -n kube-system get pods -l k8s-app=cilium -o name); do
  echo "--- $p"
  k -n kube-system exec "$p" -c cilium-agent -- hubble observe --namespace sample --last 15 2>&1 | tail -15
done
exit $fail
