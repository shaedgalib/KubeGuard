#!/usr/bin/env bash
# P1-U7 acceptance: Prometheus scrapes its targets and Grafana is healthy with dashboards loaded.
# Requests go through the API server's Service proxy with the project kubeconfig, so nothing is
# needed inside the pods (their images have no wget or curl) and no port-forward is needed.
set -uo pipefail
KC="${PROJECT_KUBECONFIG:-$HOME/.kube/kubeguard.kubeconfig}"
k() { env -u KUBECONFIG kubectl --kubeconfig "$KC" "$@"; }
fail=0
check() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (got '$2', want '$3')"; fail=1; fi; }

echo "Pods in namespace monitoring:"
k -n monitoring get pods --no-headers | awk '{print "  " $1, $2, $3}'
echo

P=/api/v1/namespaces/monitoring/services/monitoring-kube-prometheus-prometheus:9090/proxy
G=/api/v1/namespaces/monitoring/services/monitoring-grafana:80/proxy
q() { k get --raw "$P/api/v1/query?query=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1")"; }
val() { python3 -c 'import sys,json; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else 0)' 2>/dev/null || echo 0; }

down=$(q 'count(up==0)' | val)
total=$(q 'count(up)' | val)
echo "Prometheus targets: $total total, $down down"
check "no scrape target is down" "$down" "0"
check "at least one target is scraped" "$([ "$total" -gt 0 ] && echo yes || echo no)" "yes"

nodes=$(q 'count(node_uname_info)' | val)
check "node metrics from all three nodes" "$nodes" "3"

health=$(k get --raw "$G/api/health" | python3 -c 'import sys,json; print(json.load(sys.stdin)["database"])' 2>/dev/null || echo unreachable)
check "Grafana health: database" "$health" "ok"

dash=$(k -n monitoring get configmap -l grafana_dashboard=1 --no-headers | wc -l)
echo "Dashboard ConfigMaps loaded into Grafana: $dash"
check "dashboards provisioned" "$([ "$dash" -gt 0 ] && echo yes || echo no)" "yes"
exit $fail
