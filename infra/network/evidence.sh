#!/usr/bin/env bash
# P2-U5 and P2-U8: read-only evidence about the network policies and the ztunnel mutual TLS, saved in one folder.
# Usage: evidence.sh [directory]      default: ~/.local/share/kubeguard/evidence/p2-network-security (mode 700)
# Nothing is changed. The files are the input for docs/reports/P2-U5-network-policies.md and P2-U8-mtls-evidence.md.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-$HOME/.local/share/kubeguard/evidence/p2-network-security}
KC=${PROJECT_KUBECONFIG:-$HOME/.kube/kubeguard.kubeconfig}
KEY=${KG_LAB_KEY:-$HOME/.ssh/kubeguard-lab}
CONF=${NODES_CONF:-infra/libvirt/nodes.conf}
k() { env -u KUBECONFIG kubectl --kubeconfig "$KC" "$@"; }
mkdir -p "$OUT"; chmod 700 "$OUT"

{ echo "date: $(date -Is)"; echo "git: $(git branch --show-current) @ $(git rev-parse --short HEAD)"; } > "$OUT/00-context.txt"
infra/network/policies.sh status > "$OUT/10-policy-status.txt" 2>&1
k get ciliumnetworkpolicies -A > "$OUT/11-policies.txt" 2>&1
python3 infra/network/flows.py --since 10m > "$OUT/12-flows-10m.md" 2>&1
python3 infra/network/flows.py --since 10m --verdict DROPPED > "$OUT/13-flows-dropped-10m.md" 2>&1
python3 infra/network/flows.py --since 10m --verdict AUDIT > "$OUT/14-flows-audit-10m.md" 2>&1
{ k -n kube-system get configmap cilium-config -o json | jq -r '.data | to_entries[] | select(.key | test("ztunnel|encryption|policy-audit")) | "\(.key)=\(.value)"' | sort
  echo; k -n kube-system get daemonset ztunnel-cilium 2>&1
  echo; k -n kube-system get pods -l app.kubernetes.io/name=ztunnel -o wide 2>&1 | head; k -n kube-system get pods -o wide --no-headers 2>/dev/null | grep ztunnel
  echo; echo "namespaces enrolled:"; k get namespaces -l io.cilium/mtls-enabled=true --no-headers 2>&1
} > "$OUT/20-ztunnel.txt"
{ grep -v '^[[:space:]]*#' "$CONF" | grep -v '^[[:space:]]*$' | while read -r name role ip _; do
    printf '%s: ' "$name"
    ssh -n -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ubuntu@"$ip" "free -m | awk 'NR==2{print \"total \" \$2 \" MB, available \" \$7 \" MB\"}'"
  done; } > "$OUT/30-node-memory.txt" 2>&1
chmod 600 "$OUT"/*
ls -l "$OUT" | awk 'NR>1 {print $5, $9}'
echo "saved in $OUT (outside git)"
