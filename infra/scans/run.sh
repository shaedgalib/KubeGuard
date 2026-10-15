#!/usr/bin/env bash
# P2-U1 and later: run the two scanners against the cluster and keep the raw output outside git.
# Usage: run.sh <label> [all|kube-bench|kubescape]      for example: run.sh baseline
#   kube-bench  CIS Kubernetes benchmark, as read-only Jobs on every node (needs the image: internet window)
#   kubescape   NSA, MITRE and CIS frameworks from the host, with the project kubeconfig only; nothing is submitted
# Output: $KG_SCAN_DIR/<label>-<time>/ (default ~/.local/share/kubeguard/scans, mode 700) and a "latest" link.
# Both scanners only read the cluster. Read the scores with summarize.py; never type them in by hand.
set -euo pipefail
cd "$(dirname "$0")/../.."
set -a; . infra/versions.env; set +a

KC=${PROJECT_KUBECONFIG:-$HOME/.kube/kubeguard.kubeconfig}
BASE=${KG_SCAN_DIR:-$HOME/.local/share/kubeguard/scans}
FRAMEWORKS=${KUBESCAPE_FRAMEWORKS:-nsa,mitre,cis-v1.12.0}
CACHE=${KG_KUBESCAPE_CACHE:-$HOME/.local/share/kubeguard/kubescape-cache}
CONF=${NODES_CONF:-infra/libvirt/nodes.conf}

label=${1:?usage: run.sh <label> [all|kube-bench|kubescape]}
what=${2:-all}
[[ $label =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "label: lowercase letters, digits and dashes only"; exit 2; }
case $what in all|kube-bench|kubescape) ;; *) echo "usage: run.sh <label> [all|kube-bench|kubescape]"; exit 2 ;; esac

k() { env -u KUBECONFIG kubectl --kubeconfig "$KC" "$@"; }
WORKERS=$(grep -v '^[[:space:]]*#' "$CONF" | awk '$2=="worker"' | wc -l)
render() { sed -e "s|@KUBE_BENCH@|$KUBE_BENCH|g" -e "s|@BENCHMARK@|$KUBE_BENCH_BENCHMARK|g" -e "s|@WORKERS@|$WORKERS|g" "$1"; }

mkdir -p "$BASE"; chmod 700 "$BASE"
OUT="$BASE/$label-$(date +%Y%m%d-%H%M%S)"; mkdir -m 700 "$OUT"

context() {
  {
    echo "label: $label"
    echo "date: $(date -Is)"
    echo "git: $(git branch --show-current) @ $(git rev-parse --short HEAD)$(git diff --quiet HEAD -- || echo ' (uncommitted changes in the working tree)')"
    echo "kube-bench: v$KUBE_BENCH, profile $KUBE_BENCH_BENCHMARK, targets: control node master,etcd,controlplane,policies,node; workers node"
    echo "kubescape: $(env -u KUBECONFIG kubescape version 2>/dev/null | head -1 | sed 's/.*: //'), controls $KUBESCAPE_CONTROLS, frameworks $FRAMEWORKS"
    echo "kubernetes server: $(k version -o json | jq -r .serverVersion.gitVersion)"
    echo "nodes:"; k get nodes -o wide --no-headers
  } > "$OUT/context.txt"
}

wait_jobs() {  # wait_jobs <seconds> <job>...   returns when every job has finished; fails when one fails or time runs out
  local end=$(( SECONDS + $1 )) j s f c pending; shift
  while [ $SECONDS -lt $end ]; do
    pending=0
    for j in "$@"; do
      s=$(k -n scanners get job "$j" -o jsonpath='{.status.succeeded}'); f=$(k -n scanners get job "$j" -o jsonpath='{.status.failed}')
      c=$(k -n scanners get job "$j" -o jsonpath='{.spec.completions}')
      [ "${f:-0}" -gt 0 ] && { echo "job $j failed"; return 1; }
      [ "${s:-0}" -ge "${c:-1}" ] || pending=1
    done
    [ $pending = 0 ] && return 0
    sleep 5
  done
  echo "timeout waiting for: $*"; return 1
}

run_kube_bench() {
  echo "== kube-bench v$KUBE_BENCH ($KUBE_BENCH_BENCHMARK): control node plus $WORKERS workers"
  k apply -f k8s/scanners/namespace.yaml >/dev/null
  k -n scanners delete job -l app.kubernetes.io/name=kube-bench --ignore-not-found --wait=true >/dev/null
  render k8s/scanners/kube-bench-control.yaml.tpl | k apply -f - >/dev/null
  render k8s/scanners/kube-bench-worker.yaml.tpl | k apply -f - >/dev/null
  if ! wait_jobs 600 kube-bench-control kube-bench-worker; then
    k -n scanners get pods -o wide; k -n scanners describe pods | grep -A12 '^Events' | head -40; return 1
  fi
  local pod node
  while read -r pod node; do
    k -n scanners logs "$pod" > "$OUT/kube-bench-$node.log"
    echo "saved kube-bench-$node.log ($(wc -c < "$OUT/kube-bench-$node.log") bytes)"
  done < <(k -n scanners get pods -l app.kubernetes.io/name=kube-bench -o jsonpath='{range .items[*]}{.metadata.name} {.spec.nodeName}{"\n"}{end}')
  k -n scanners delete job -l app.kubernetes.io/name=kube-bench --wait=true >/dev/null
}

run_kubescape() {
  command -v kubescape >/dev/null || { echo "kubescape is missing: run make kubescape-install"; return 1; }
  echo "== kubescape ($FRAMEWORKS, controls $KUBESCAPE_CONTROLS)"
  mkdir -p "$CACHE"; chmod 700 "$CACHE"
  if ! env -u KUBECONFIG kubescape scan framework "$FRAMEWORKS" --kubeconfig "$KC" --cache-dir "$CACHE" \
      --keep-local --host-scan=false --controls-version "$KUBESCAPE_CONTROLS" \
      --controls-config infra/scans/kubescape/controls-config.json --exceptions infra/scans/kubescape/exceptions.json \
      --fail-on-degraded-config --scan-timeout 20m \
      --format json --output "$OUT/kubescape.json" > "$OUT/kubescape.log" 2>&1; then
    tail -20 "$OUT/kubescape.log"; return 1
  fi
  echo "saved kubescape.json ($(wc -c < "$OUT/kubescape.json") bytes)"
}

context
case $what in
  all) run_kube_bench; run_kubescape ;;
  kube-bench) run_kube_bench ;;
  kubescape) run_kubescape ;;
esac
( cd "$OUT" && sha256sum -- * > SHA256SUMS )
ln -sfn "$OUT" "$BASE/latest"
echo; echo "Saved in $OUT (outside git)"
if [ -x infra/scans/summarize.py ]; then infra/scans/summarize.py "$OUT"; fi
