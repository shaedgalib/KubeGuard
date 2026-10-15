#!/usr/bin/env bash
# P1-U9: etcd snapshot, restore and a full drill on the single control-plane node.
# Usage: etcd.sh snapshot | restore <snapshot-file> | drill
# The etcd image already contains etcdctl and etcdutl, so everything runs through "crictl exec"
# on the node. Snapshots are copied to the host OUTSIDE the repository: etcd holds all Secrets.
# With encryption at rest (P2-U6) the Secrets in a snapshot are readable only with the key of the node that
# wrote it. A snapshot is therefore saved with a small file etcd-<time>.key-id that names that key (the first
# 12 characters of the checksum of the encryption configuration). The key itself is NOT stored next to the
# snapshot: the hardening role keeps a copy in $KG_KEY_BACKUP_DIR, and restore warns when the keys differ.
set -euo pipefail
CP=${KG_CP_IP:-10.77.0.10}
NAME=kg-control-1
KEY=${KG_LAB_KEY:-$HOME/.ssh/kubeguard-lab}
KC=${PROJECT_KUBECONFIG:-$HOME/.kube/kubeguard.kubeconfig}
BACKUP_DIR=${KG_BACKUP_DIR:-$HOME/.local/share/kubeguard/etcd-backups}
PKI=/etc/kubernetes/pki/etcd
ENC_CONF=/etc/kubernetes/encryption/encryption-config.yaml      # written by the hardening role (P2-U6)
KEY_DIR=${KG_KEY_BACKUP_DIR:-$HOME/.local/share/kubeguard/encryption-keys}
SSH_OPTS=(-i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

node()   { ssh -n "${SSH_OPTS[@]}" ubuntu@"$CP" "$@"; }     # no stdin
node_i() { ssh "${SSH_OPTS[@]}" ubuntu@"$CP" "$@"; }        # reads stdin
k()      { env -u KUBECONFIG kubectl --kubeconfig "$KC" "$@"; }
ok()   { echo "PASS  $*"; }
bad()  { echo "FAIL  $*"; FAILED=1; }
info() { echo "INFO  $*"; }
FAILED=0

# The key in use on the node: first 12 characters of the checksum of its encryption configuration (empty when none).
key_id() { node "sudo sha256sum $ENC_CONF 2>/dev/null | cut -c1-12" || true; }
secrets_readable() {  # false when the API cannot decrypt a stored Secret (wrong or missing key)
  local i; for i in $(seq 1 10); do k get secrets -A -o name >/dev/null 2>&1 && return 0; sleep 3; done; return 1
}

# etcdctl/etcdutl inside the running etcd container
ETCDCTL='id=$(sudo crictl ps --name etcd -q | head -1); sudo crictl exec $id etcdctl --endpoints=https://127.0.0.1:2379 --cacert='$PKI'/ca.crt --cert='$PKI'/server.crt --key='$PKI'/server.key'

snapshot() {  # prints the path of the saved snapshot on the last line
  local ts file remote
  ts=$(date +%Y%m%d-%H%M%S); file="$BACKUP_DIR/etcd-$ts.db"; remote=/var/lib/etcd/snapshot-$ts.db
  mkdir -p "$BACKUP_DIR"; chmod 700 "$BACKUP_DIR"
  node "$ETCDCTL snapshot save $remote" >&2
  node 'id=$(sudo crictl ps --name etcd -q | head -1); sudo crictl exec $id etcdutl snapshot status '"$remote"' -w table' >&2
  node "sudo cat $remote" > "$file"; chmod 600 "$file"
  node "sudo rm -f $remote"
  echo "copied to host: $file ($(stat -c %s "$file") bytes, sha256 $(sha256sum "$file" | cut -c1-16)...)" >&2
  local kid; kid=$(key_id)
  if [ -n "$kid" ]; then
    ( umask 077; echo "$kid" > "${file%.db}.key-id" )
    echo "encryption key $kid recorded in ${file%.db}.key-id" >&2
    [ -f "$KEY_DIR/$NAME-$kid.yaml" ] || echo "WARNING: no copy of that key in $KEY_DIR; without the key the Secrets in this snapshot cannot be read" >&2
  fi
  echo "$file"
}

restore() {  # restore <snapshot-file>
  local file=$1 ts; ts=$(date +%Y%m%d-%H%M%S)
  [ -f "$file" ] || { echo "no such snapshot: $file"; exit 2; }
  local want have; want=$(cat "${file%.db}.key-id" 2>/dev/null || true); have=$(key_id)
  if [ -n "$want" ] && [ "$want" != "$have" ]; then
    echo "WARNING: this snapshot was written with encryption key $want; the node has '${have:-none}'."
    echo "  Secrets in the snapshot can be read only if the node's configuration still lists that key."
    echo "  A copy is in $KEY_DIR/$NAME-$want.yaml (see docs/runbooks/hardening.md, section Encryption key)."
  elif [ -z "$want" ] && [ -n "$have" ]; then
    echo "note: this snapshot has no key-id file; it predates encryption or was taken without it (the identity fallback reads such Secrets)."
  fi
  echo "uploading snapshot to $NAME"
  node_i "sudo tee /var/lib/etcd/restore.db >/dev/null" < "$file"
  node_i "TS=$ts NAME=$NAME CP=$CP bash -s" <<'EOS'
set -euo pipefail
id=$(sudo crictl ps --name etcd -q | head -1)
# 1. build the restored data directory inside the data volume, while etcd still runs
sudo crictl exec "$id" etcdutl snapshot restore /var/lib/etcd/restore.db \
  --name "$NAME" --initial-cluster "$NAME=https://$CP:2380" \
  --initial-advertise-peer-urls "https://$CP:2380" --data-dir /var/lib/etcd/restored
# 2. stop the API server and etcd by moving their manifests away
sudo mkdir -p /etc/kubernetes/manifests-paused
sudo mv /etc/kubernetes/manifests/etcd.yaml /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/manifests-paused/
for _ in $(seq 1 60); do
  [ -z "$(sudo crictl ps --name '^etcd$|^kube-apiserver$' -q)" ] && break; sleep 2
done
# 3. swap the data directories, keeping the old one
sudo mv /var/lib/etcd/member "/var/lib/etcd/member.before-restore-$TS"
sudo mv /var/lib/etcd/restored/member /var/lib/etcd/member
sudo rmdir /var/lib/etcd/restored
sudo rm -f /var/lib/etcd/restore.db
# 4. start them again
sudo mv /etc/kubernetes/manifests-paused/etcd.yaml /etc/kubernetes/manifests-paused/kube-apiserver.yaml /etc/kubernetes/manifests/
for _ in $(seq 1 90); do
  sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get --raw /readyz >/dev/null 2>&1 && { echo "API ready"; exit 0; }
  sleep 2
done
echo "API did not become ready in 180 s"; exit 1
EOS
  secrets_readable && echo "Secrets readable after the restore" \
    || { echo "FAIL  Secrets cannot be read after the restore: the node's encryption key does not match the snapshot"; return 1; }
}

drill() {
  local stamp; stamp=$(date +%s)
  echo "== 0. wait for the API"
  for _ in $(seq 1 60); do k get --raw /readyz >/dev/null 2>&1 && break; sleep 5; done
  k get --raw /readyz >/dev/null 2>&1 || { echo "API not ready after 300 s"; exit 1; }
  echo "== 1. state before the snapshot"
  k create configmap drill-before --from-literal=stamp="$stamp" >/dev/null
  k get configmap drill-before >/dev/null && ok "configmap drill-before created"
  k create secret generic drill-secret-before --from-literal=stamp="$stamp" >/dev/null
  k get secret drill-secret-before >/dev/null && ok "secret drill-secret-before created"
  echo "== 2. snapshot"
  local file; file=$(snapshot)
  if [ -f "${file%.db}.key-id" ]; then info "Secrets in this snapshot are encrypted with key $(cat "${file%.db}.key-id")"
  else info "the node has no encryption configuration: this snapshot holds Secrets in plaintext"; fi
  echo "== 3. change the cluster after the snapshot"
  k delete configmap drill-before >/dev/null
  k create configmap drill-after --from-literal=stamp="$stamp" >/dev/null
  k get configmap drill-after >/dev/null && ! k get configmap drill-before >/dev/null 2>&1 \
    && ok "drill-before deleted, drill-after created" || bad "the change did not apply"
  k delete secret drill-secret-before >/dev/null
  k create secret generic drill-secret-after --from-literal=stamp="$stamp" >/dev/null
  echo "== 4. restore from the snapshot"
  restore "$file"
  echo "== 5. verify"
  sleep 5
  k get configmap drill-before >/dev/null 2>&1 && ok "drill-before is back (state as of the snapshot)" || bad "drill-before missing after restore"
  k get configmap drill-after  >/dev/null 2>&1 && bad "drill-after still exists (should be gone)" || ok "drill-after is gone"
  [ "$(k get secret drill-secret-before -o jsonpath='{.data.stamp}' 2>/dev/null | base64 -d 2>/dev/null)" = "$stamp" ] \
    && ok "drill-secret-before is back and its value decrypts correctly" || bad "drill-secret-before missing or unreadable after the restore"
  k get secret drill-secret-after >/dev/null 2>&1 && bad "drill-secret-after still exists (should be gone)" || ok "drill-secret-after is gone"
  local notready; notready=$(k get nodes --no-headers | awk '$2!="Ready"' | wc -l)
  [ "$notready" = 0 ] && ok "all nodes Ready" || bad "$notready node(s) not Ready"
  k -n kube-system get pods --no-headers | awk '$3!="Running"' | grep -q . && bad "some kube-system pods are not Running" || ok "kube-system pods Running"
  k delete configmap drill-before drill-after --ignore-not-found >/dev/null
  k delete secret drill-secret-before drill-secret-after --ignore-not-found >/dev/null
  echo "snapshot kept at: $file"
  exit $FAILED
}

case "${1:-}" in
  snapshot) snapshot ;;
  restore)  restore "${2:?usage: etcd.sh restore <snapshot-file>}" ;;
  drill)    drill ;;
  *) echo "usage: $0 snapshot|restore <file>|drill"; exit 2 ;;
esac
