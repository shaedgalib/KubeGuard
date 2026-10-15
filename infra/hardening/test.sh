#!/usr/bin/env bash
# Tests for the hardening controls (P2). Each test tries the bad thing and passes only when it is refused,
# or reads the effective setting from the running cluster. P2-U10 collects them under: make test-hardening
# Usage: test.sh [all | <test> ...]
# Tests: anonymous external-ips profiling files kubelet-tls tls pid-limit seccomp etcd-encryption audit
# Test pods use busybox:latest, which is already on both workers (no pull, so this also runs isolated).
set -uo pipefail
cd "$(dirname "$0")/../.."

KC=${PROJECT_KUBECONFIG:-$HOME/.kube/kubeguard.kubeconfig}
CONF=${NODES_CONF:-infra/libvirt/nodes.conf}
KEY=${KG_LAB_KEY:-$HOME/.ssh/kubeguard-lab}
NS=hardening-test
IMAGE=busybox:latest
FAILED=0

ok()   { echo "PASS  $*"; }
bad()  { echo "FAIL  $*"; FAILED=1; }
info() { echo "INFO  $*"; }
k()    { env -u KUBECONFIG kubectl --kubeconfig "$KC" "$@"; }
rows() { grep -v '^[[:space:]]*#' "$CONF" | grep -v '^[[:space:]]*$'; }
CP_NAME=$(rows | awk '$2=="control" {print $1; exit}')
CP=$(rows | awk '$2=="control" {print $3; exit}')
node() { local ip=$1; shift; ssh -n -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 \
           -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ubuntu@"$ip" "$@"; }
code() { curl -sk -o /dev/null -m 10 -w '%{http_code}' "$1"; }

# The test namespace is created on first use and removed when the script ends. It is labelled baseline:
# the seccomp test needs a pod without a seccompProfile, which the restricted level (P2-U4) would refuse.
NS_MADE=0
ns_up() {
  [ $NS_MADE = 1 ] && return 0
  # The previous run may still be deleting the namespace (cleanup does not wait); creating objects in it would fail.
  if [ -n "$(k get namespace $NS -o jsonpath='{.metadata.deletionTimestamp}' 2>/dev/null)" ]; then
    k wait --for=delete namespace/$NS --timeout=120s >/dev/null 2>&1
  fi
  k get namespace $NS >/dev/null 2>&1 || k create namespace $NS >/dev/null
  k label namespace $NS pod-security.kubernetes.io/enforce=baseline --overwrite >/dev/null
  NS_MADE=1
}
cleanup() { [ $NS_MADE = 1 ] && k delete namespace $NS --ignore-not-found --wait=false >/dev/null 2>&1; }
trap cleanup EXIT

t_anonymous() {
  echo "== anonymous access (CIS 1.2.1)"
  local c
  c=$(code "https://$CP:6443/version");               [ "$c" = 401 ] && ok "anonymous GET /version is refused (401)" || bad "anonymous GET /version answered $c, want 401"
  c=$(code "https://$CP:6443/api/v1/namespaces");     [ "$c" = 401 ] && ok "anonymous GET /api/v1/namespaces is refused (401)" || bad "anonymous GET /api/v1/namespaces answered $c, want 401"
  c=$(code "https://$CP:6443/readyz");                [ "$c" = 200 ] && ok "anonymous GET /readyz is still accepted (200): the API server probes work" || bad "anonymous GET /readyz answered $c, want 200"
}

t_external_ips() {
  echo "== Services with external IPs (CIS 1.2.3)"
  ns_up
  local out
  if out=$(k -n $NS create --dry-run=server -f - 2>&1 <<'EOF'
apiVersion: v1
kind: Service
metadata: {name: externalip-probe}
spec:
  selector: {app: none}
  ports: [{port: 80}]
  externalIPs: ["192.0.2.10"]
EOF
  ); then bad "a Service with externalIPs was accepted"; else
    grep -qi 'externalIPs' <<<"$out" && ok "a Service with externalIPs is rejected at admission" || bad "rejected, but not for externalIPs: $out"
  fi
}

t_profiling() {
  echo "== profiling endpoints (CIS 1.2.15, 1.3.2, 1.4.1)"
  local out
  out=$(k get --raw /debug/pprof/ 2>&1)
  grep -qi 'NotFound' <<<"$out" && ok "the API server does not serve /debug/pprof/" || bad "/debug/pprof/ is served: ${out:0:80}"
  node "$CP" 'pgrep -af "^kube-controller-manager" | grep -F -- "--profiling=false" >/dev/null' && ok "kube-controller-manager runs with --profiling=false" || bad "kube-controller-manager lacks --profiling=false"
  node "$CP" 'pgrep -af "^kube-scheduler" | grep -F -- "--profiling=false" >/dev/null' && ok "kube-scheduler runs with --profiling=false" || bad "kube-scheduler lacks --profiling=false"
}

t_files() {
  echo "== file permissions and ownership (CIS 4.1.1, 4.1.9, 1.1.12)"
  local name role ip got
  while read -r name role ip _; do
    got=$(node "$ip" 'sudo stat -c "%a %U:%G" /usr/lib/systemd/system/kubelet.service /var/lib/kubelet/config.yaml' | paste -sd' ')
    [ "$got" = "600 root:root 600 root:root" ] && ok "$name: kubelet.service and config.yaml are 600 root:root" || bad "$name: kubelet.service and config.yaml are '$got'"
    if [ "$role" = control ]; then
      got=$(node "$ip" 'sudo stat -c "%a %U:%G" /var/lib/etcd')
      [ "$got" = "700 etcd:etcd" ] && ok "$name: /var/lib/etcd is 700 etcd:etcd" || bad "$name: /var/lib/etcd is '$got'"
    fi
  done < <(rows)
}

t_kubelet_tls() {
  echo "== kubelet serving certificates (CIS 1.2.5)"
  local ca name role ip
  node "$CP" 'pgrep -af "^kube-apiserver" | grep -F -- "--kubelet-certificate-authority=" >/dev/null' \
    && ok "kube-apiserver verifies kubelet certificates (--kubelet-certificate-authority is set)" \
    || bad "kube-apiserver does not verify kubelet certificates (no --kubelet-certificate-authority)"
  ca=$(mktemp); k -n kube-system get configmap kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' > "$ca"
  while read -r name role ip _; do
    if echo | openssl s_client -connect "$ip:10250" -CAfile "$ca" -verify_return_error -verify_ip "$ip" 2>&1 | grep 'Verify return code: 0 (ok)' >/dev/null; then
      ok "$name: the kubelet serves a certificate signed by the cluster CA for $ip"
    else bad "$name: the kubelet certificate does not verify against the cluster CA"; fi
    [ "$(k get --raw "/api/v1/nodes/$name/proxy/healthz" 2>/dev/null)" = ok ] \
      && ok "$name: the API server reaches the kubelet" || bad "$name: the API server cannot reach the kubelet"
  done < <(rows)
  rm -f "$ca"
}

negotiated() {  # negotiated <host:port> <cipher list>: the cipher a TLS 1.2 handshake settled on, empty when it failed
  echo | timeout 10 openssl s_client -connect "$1" -tls1_2 -cipher "$2" 2>&1 | sed -n 's/.*Cipher is \([A-Z0-9-]*\).*/\1/p' | grep -v '^$' | head -1
}

t_tls() {
  echo "== strong TLS ciphers (CIS 1.2.29, 4.2.12)"
  local label target got
  # The API server and the kubelet of every node. A suite from the configured list must work; a CBC/SHA-1 suite must not.
  # Both key types are offered, because the kubelet certificate is RSA before and ECDSA after the serving-certificate bootstrap.
  while read -r label target; do
    got=$(negotiated "$target" 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256')
    [ -n "$got" ] && ok "$label: a TLS 1.2 handshake with $got works" || bad "$label: no handshake with an AES-GCM suite (is the service reachable?)"
    got=$(negotiated "$target" 'ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA')
    [ -z "$got" ] && ok "$label: the weak suite AES128-SHA (CBC, SHA-1) is refused" || bad "$label: the weak suite $got is accepted"
  done < <(echo "kube-apiserver $CP:6443"; rows | awk '{print "kubelet-" $1 " " $3 ":10250"}')
}

# A pod that stays Running on a chosen worker; prints nothing, leaves the pod for the caller to inspect.
probe_pod() {  # probe_pod <pod> <worker> <shell command>
  ns_up
  k -n $NS delete pod "$1" --ignore-not-found --wait=true >/dev/null 2>&1
  k -n $NS run "$1" --image=$IMAGE --image-pull-policy=IfNotPresent --restart=Never \
    --overrides="{\"spec\":{\"nodeName\":\"$2\"}}" --command -- sh -c "$3" >/dev/null 2>&1 || return 1
  k -n $NS wait --for=condition=Ready pod/"$1" --timeout=90s >/dev/null 2>&1
}

t_pid_limit() {
  echo "== PID limit per pod (CIS 4.2.13)"
  local name role ip uid got
  while read -r name role ip _; do
    [ "$role" = worker ] || continue
    probe_pod pid-probe "$name" 'sleep 120' || { bad "$name: the probe pod did not start"; continue; }
    uid=$(k -n $NS get pod pid-probe -o jsonpath='{.metadata.uid}' | tr - _)
    got=$(node "$ip" "sudo cat \$(sudo find /sys/fs/cgroup/kubepods.slice -maxdepth 3 -type d -name 'kubepods-*-pod${uid}.slice' | head -1)/pids.max" 2>/dev/null)
    [ "$got" = 4096 ] && ok "$name: the pod cgroup allows at most $got processes" || bad "$name: pids.max of the pod is '$got', want 4096"
    k -n $NS delete pod pid-probe --wait=false >/dev/null 2>&1
  done < <(rows)
}

t_seccomp() {
  echo "== default seccomp profile (CIS 4.2.14)"
  local name role ip got
  while read -r name role ip _; do
    [ "$role" = worker ] || continue
    probe_pod seccomp-probe "$name" 'grep ^Seccomp: /proc/self/status; sleep 120' || { bad "$name: the probe pod did not start"; continue; }
    got=$(k -n $NS logs seccomp-probe 2>/dev/null | awk '/^Seccomp:/ {print $2}')
    [ "$got" = 2 ] && ok "$name: a pod without a seccomp profile runs with the runtime default filter (Seccomp: 2)" || bad "$name: Seccomp is '$got' in a pod without a profile, want 2"
    k -n $NS delete pod seccomp-probe --wait=false >/dev/null 2>&1
  done < <(rows)
}

ETCDCTL='id=$(sudo crictl ps --name etcd -q | head -1); sudo crictl exec $id etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key'

t_etcd_encryption() {
  echo "== Secrets encrypted at rest (CIS 1.2.27, 1.2.28)"
  ns_up
  local value="kg-enc-probe-$RANDOM$RANDOM" head hits back bare
  k -n $NS delete secret enc-probe --ignore-not-found >/dev/null 2>&1
  k -n $NS create secret generic enc-probe --from-literal=value="$value" >/dev/null || { bad "could not create the probe Secret"; return; }
  # The record is protobuf and the Secret data comes after the metadata, so the value is searched in the whole record, not in a prefix.
  head=$(node "$CP" "$ETCDCTL get /registry/secrets/$NS/enc-probe --print-value-only | head -c 40 | tr -c '[:print:]' '.'")
  hits=$(node "$CP" "$ETCDCTL get /registry/secrets/$NS/enc-probe --print-value-only | grep -acF '$value'")
  if [ -z "$head" ]; then bad "could not read the probe Secret from etcd"; k -n $NS delete secret enc-probe --ignore-not-found >/dev/null 2>&1; return; fi
  case $hits in
    0) ok "the plaintext value is not found anywhere in the etcd record" ;;
    ''|*[!0-9]*) bad "could not search the etcd record" ;;
    *) bad "the Secret is stored as plaintext in etcd (the value is in the record)" ;;
  esac
  grep -q 'k8s:enc:secretbox:v1:key1' <<<"$head" && ok "the etcd record carries the prefix k8s:enc:secretbox:v1:key1" || bad "no secretbox prefix in the etcd record: ${head:0:40}"
  back=$(k -n $NS get secret enc-probe -o jsonpath='{.data.value}' | base64 -d)
  [ "$back" = "$value" ] && ok "the API server still returns the decrypted value" || bad "the API server returned a different value"
  bare=$(node "$CP" "for key in \$($ETCDCTL get /registry/secrets --prefix --keys-only | grep .); do $ETCDCTL get \$key --print-value-only | head -c 12 | grep -q '^k8s:enc:' || echo \$key; done" 2>/dev/null)
  [ -z "$bare" ] && ok "every Secret in etcd is stored encrypted" || bad "Secrets stored without encryption: $(echo "$bare" | wc -l) (first: $(echo "$bare" | head -1))"
  k -n $NS delete secret enc-probe --ignore-not-found >/dev/null 2>&1
}

t_audit() {
  echo "== API audit log (CIS 1.2.16 to 1.2.19, 3.2.1, 3.2.2)"
  ns_up
  local tag="audit-probe-$RANDOM$RANDOM" value="kg-audit-secret-$RANDOM$RANDOM" log=/var/log/kubernetes/audit/audit.log lvl hits
  k create namespace "$tag" >/dev/null && k -n $NS create secret generic "$tag" --from-literal=value="$value" >/dev/null \
    && k -n $NS get secret "$tag" >/dev/null && k delete namespace "$tag" --wait=false >/dev/null
  sleep 3
  [ "$(node "$CP" "sudo stat -c '%a %U' $log")" = "600 root" ] && ok "the audit log exists and is 600 root" || bad "the audit log is missing or has wrong permissions"
  lvl=$(node "$CP" "sudo grep -F '\"$tag\"' $log | jq -r 'select(.verb==\"create\" and .objectRef.resource==\"namespaces\") | .level' | head -1")
  [ "$lvl" = Request ] && ok "creating a namespace is logged at level Request" || bad "namespace creation logged at level '$lvl', want Request"
  lvl=$(node "$CP" "sudo grep -F '\"$tag\"' $log | jq -r 'select(.verb==\"get\" and .objectRef.resource==\"secrets\") | .level' | head -1")
  [ "$lvl" = Metadata ] && ok "reading a Secret is logged at level Metadata (who and when, no content)" || bad "Secret read logged at level '$lvl', want Metadata"
  hits=$(node "$CP" "sudo grep -cF '$value' $log" 2>/dev/null)
  case $hits in
    0) ok "no Secret value appears in the audit log" ;;
    ''|*[!0-9]*) bad "could not search the audit log" ;;
    *) bad "a Secret value appears in the audit log ($hits lines)" ;;
  esac
  info "audit log size: $(node "$CP" "sudo du -sh $(dirname $log) | cut -f1")"
}

ALL=(anonymous external-ips profiling files kubelet-tls tls pid-limit seccomp etcd-encryption audit)
want=("$@"); [ ${#want[@]} -eq 0 ] || [ "${want[0]}" = all ] && want=("${ALL[@]}")
for t in "${want[@]}"; do
  fn="t_${t//-/_}"
  if declare -F "$fn" >/dev/null; then "$fn"; else echo "unknown test: $t (tests: ${ALL[*]})"; exit 2; fi
done
echo
[ $FAILED = 0 ] && echo "ALL PASSED" || echo "SOME TESTS FAILED"
exit $FAILED
