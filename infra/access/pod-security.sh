#!/usr/bin/env bash
# P2-U4: set or check the Pod Security Admission labels from k8s/access/pod-security.conf.
# Usage: pod-security.sh apply | check      (project kubeconfig only; namespaces that do not exist yet are skipped)
set -uo pipefail
cd "$(dirname "$0")/../.."
KC=${PROJECT_KUBECONFIG:-$HOME/.kube/kubeguard.kubeconfig}
CONF=${PSA_CONF:-k8s/access/pod-security.conf}
P=pod-security.kubernetes.io
k() { env -u KUBECONFIG kubectl --kubeconfig "$KC" "$@"; }
rows() { grep -v '^[[:space:]]*#' "$CONF" | grep -v '^[[:space:]]*$'; }
label() { k get namespace "$1" -o jsonpath="{.metadata.labels.pod-security\.kubernetes\.io/$2}" 2>/dev/null; }

apply() {
  local ns enforce audit warn rc=0
  while read -r ns enforce audit warn; do
    k get namespace "$ns" >/dev/null 2>&1 || { echo "skip   $ns (does not exist yet)"; continue; }
    k label namespace "$ns" --overwrite "$P/enforce=$enforce" "$P/audit=$audit" >/dev/null || { rc=1; continue; }
    if [ "$warn" = "-" ]; then [ -z "$(label "$ns" warn)" ] || k label namespace "$ns" "$P/warn-" >/dev/null
    else k label namespace "$ns" --overwrite "$P/warn=$warn" >/dev/null; fi
    echo "set    $ns: enforce=$enforce audit=$audit warn=$warn"
  done < <(rows)
  return $rc
}

check() {
  local ns enforce audit warn rc=0 got
  while read -r ns enforce audit warn; do
    k get namespace "$ns" >/dev/null 2>&1 || { echo "skip   $ns (does not exist)"; continue; }
    got="$(label "$ns" enforce) $(label "$ns" audit) $(label "$ns" warn)"; got=${got% }
    want="$enforce $audit $warn"; [ "$warn" = "-" ] && want="$enforce $audit"
    if [ "$got" = "$want" ]; then echo "PASS   $ns: enforce=$enforce audit=$audit warn=$warn"
    else echo "FAIL   $ns: labels are '$got', the table says '$want'"; rc=1; fi
  done < <(rows)
  return $rc
}

case "${1:-}" in apply) apply ;; check) check ;; *) echo "usage: $0 apply|check"; exit 2 ;; esac
