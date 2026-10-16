#!/usr/bin/env bash
# Tests for the hardening controls (P2). Each test tries the bad thing and passes only when it is refused,
# or reads the effective setting from the running cluster. P2-U10 collects them under: make test-hardening
# Usage: test.sh [all | <test> ...]
# Tests: anonymous external-ips profiling files kubelet-tls tls pid-limit seccomp etcd-encryption audit rbac psa kyverno
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
TEMP_NS=()   # namespaces made by single tests (audit probe, policy tests); removed at exit even when a step in between failed
cleanup() {
  local t
  [ $NS_MADE = 1 ] && k delete namespace $NS --ignore-not-found --wait=false >/dev/null 2>&1
  for t in "${TEMP_NS[@]}"; do k delete namespace "$t" --ignore-not-found --wait=false >/dev/null 2>&1; done
  return 0
}
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
  k -n $NS apply -f - >/dev/null 2>&1 <<EOF || return 1
apiVersion: v1
kind: Pod
metadata: {name: $1}
spec:
  nodeName: $2
  restartPolicy: Never
  containers:
    - name: probe
      image: $IMAGE
      imagePullPolicy: IfNotPresent
      command: [sh, -c, "$3"]
      resources:
        requests: {cpu: 10m, memory: 8Mi}
        limits: {cpu: 50m, memory: 32Mi}
EOF
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
  TEMP_NS+=("$tag")
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

t_rbac() {
  echo "== RBAC least privilege (CIS 5.1.1 to 5.1.13, P2-U3)"
  local out got sa ns
  out=$(k get clusterroles,roles -A -o json | jq -r '.items[]
        | select((.metadata.labels["kubernetes.io/bootstrapping"] // "") != "rbac-defaults")
        | select(.metadata.name | test("^(system|kubeadm):") | not)
        | select([.rules[]? | select((.verbs | index("*")) or (.resources | index("*")) or (.apiGroups | index("*")))] | length > 0)
        | .kind + "/" + (.metadata.namespace // "-") + "/" + .metadata.name')
  [ -z "$out" ] && ok "no role with a wildcard exists outside the built-in roles" || bad "roles with a wildcard: $(paste -sd' ' <<<"$out")"
  out=$(k get clusterrolebindings,rolebindings -A -o json | jq -r '.items[] | select(.roleRef.name == "cluster-admin") | .subjects[]? | .kind + ":" + .name' | sort | paste -sd' ')
  [ "$out" = "Group:kubeadm:cluster-admins Group:system:masters" ] && ok "cluster-admin is bound to system:masters and kubeadm:cluster-admins only" || bad "cluster-admin is bound to: $out"
  for sa in monitoring-grafana monitoring-kube-state-metrics; do
    got=$(k auth can-i list secrets --all-namespaces --as=system:serviceaccount:monitoring:$sa 2>&1)
    [ "$got" = no ] && ok "$sa cannot list Secrets in all namespaces" || bad "$sa can list Secrets in all namespaces (answer: $got)"
  done
  for ns in sample default; do
    got=$(k -n $ns get serviceaccount default -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null)
    [ "$got" = false ] && ok "the default service account in $ns does not mount an API token" || bad "the default service account in $ns mounts an API token (automountServiceAccountToken: '${got:-unset}')"
  done
}

# A Pod manifest for the policy tests. Arguments: name, image, privileged (true or false), limits (true or false).
pod_yaml() {
  cat <<EOF
apiVersion: v1
kind: Pod
metadata: {name: $1}
spec:
  containers:
    - name: c
      image: $2
      command: [sleep, "1"]
$([ "$3" = true ] && echo '      securityContext: {privileged: true}')
$([ "$4" = true ] && echo '      resources: {requests: {cpu: 10m, memory: 8Mi}, limits: {cpu: 50m, memory: 32Mi}}')
EOF
}
# The manifest is passed as an argument, not through a pipe: ok and bad must run in this shell, or a failure would be lost.
# expect_denied <label> <pattern> <namespace> <manifest>: a server-side dry run must be refused and the message must match.
expect_denied() {
  local out; out=$(k -n "$3" apply --dry-run=server -f - 2>&1 <<<"$4")
  if grep -q "$2" <<<"$out"; then ok "$1"; else bad "$1: expected a refusal naming '$2', got: ${out:0:170}"; fi
}
# expect_accepted <label> <namespace> <manifest>
expect_accepted() {
  local out; out=$(k -n "$2" apply --dry-run=server -f - 2>&1 <<<"$3")
  if grep -q 'server dry run' <<<"$out" && ! grep -qiE 'error|forbidden|denied' <<<"$out"; then ok "$1"; else bad "$1: not accepted: ${out:0:170}"; fi
}

t_psa() {
  echo "== Pod Security Admission (P2-U4)"
  local l img=docker.io/library/busybox:1.37 m
  while read -r l; do
    case $l in PASS*) ok "${l#PASS   }" ;; FAIL*) bad "${l#FAIL   }" ;; esac
  done < <(infra/access/pod-security.sh check)
  expect_denied "a privileged pod is rejected in the restricted namespace sample" 'violates PodSecurity "restricted' sample "$(pod_yaml psa-privileged $img true true)"
  expect_denied "a pod without the restricted settings is rejected in sample" 'violates PodSecurity "restricted' sample "$(pod_yaml psa-plain $img false true)"
  expect_denied "a hostPath pod is rejected in default (baseline)" 'violates PodSecurity "baseline' default "$(pod_yaml psa-hostpath $img false true; printf '  volumes: [{name: h, hostPath: {path: /etc}}]\n')"
  m=$(cat <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: psa-compliant}
spec:
  securityContext: {runAsNonRoot: true, runAsUser: 1000, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: c
      image: docker.io/library/busybox:1.37
      command: [sleep, "1"]
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
      resources: {requests: {cpu: 10m, memory: 8Mi}, limits: {cpu: 50m, memory: 32Mi}}
EOF
)
  expect_accepted "a pod that follows the restricted profile is accepted in sample" sample "$m"
}

t_kyverno() {
  echo "== Kyverno policies (P2-U7)"
  local ns=hardening-policy-test img=docker.io/library/busybox:1.37 m
  k get namespace $ns >/dev/null 2>&1 || k create namespace $ns >/dev/null
  TEMP_NS+=("$ns")
  expect_denied "a privileged pod is refused by disallow-privileged-containers" disallow-privileged-containers $ns "$(pod_yaml k-privileged $img true true)"
  expect_denied "a pod without limits is refused by require-resource-limits" require-resource-limits $ns "$(pod_yaml k-nolimits $img false false)"
  expect_denied "an image from evil.example.com is refused by restrict-image-registries" restrict-image-registries $ns "$(pod_yaml k-registry evil.example.com/app:1 false true)"
  expect_denied "an image from ghcr.io (not on the list) is refused by restrict-image-registries" restrict-image-registries $ns "$(pod_yaml k-registry2 ghcr.io/example/app:1 false true)"
  m=$(cat <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: k-autogen}
spec:
  replicas: 1
  selector: {matchLabels: {app: k-autogen}}
  template:
    metadata: {labels: {app: k-autogen}}
    spec:
      containers:
        - name: c
          image: docker.io/library/busybox:1.37
          command: [sleep, "1"]
          securityContext: {privileged: true}
          resources: {requests: {cpu: 10m, memory: 8Mi}, limits: {cpu: 50m, memory: 32Mi}}
EOF
)
  expect_denied "a Deployment with a privileged container is refused when it is created (autogen)" disallow-privileged-containers $ns "$m"
  expect_accepted "a pod with limits, no privilege and an allowed registry is accepted" $ns "$(pod_yaml k-ok $img false true)"
  expect_accepted "an image name without a registry (docker.io) is accepted" $ns "$(pod_yaml k-ok2 nginx:1.27-alpine false true)"
  expect_accepted "an image from quay.io is accepted" $ns "$(pod_yaml k-ok3 quay.io/cilium/cilium:v1.20.2 false true)"
  expect_accepted "the system namespace monitoring is outside the policies (documented exclusion)" monitoring "$(pod_yaml k-system $img false false)"
}

ALL=(anonymous external-ips profiling files kubelet-tls tls pid-limit seccomp etcd-encryption audit rbac psa kyverno)
want=("$@"); [ ${#want[@]} -eq 0 ] || [ "${want[0]}" = all ] && want=("${ALL[@]}")
for t in "${want[@]}"; do
  fn="t_${t//-/_}"
  if declare -F "$fn" >/dev/null; then "$fn"; else echo "unknown test: $t (tests: ${ALL[*]})"; exit 2; fi
done
echo
[ $FAILED = 0 ] && echo "ALL PASSED" || echo "SOME TESTS FAILED"
exit $FAILED
