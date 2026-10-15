#!/usr/bin/env bash
# P2-U6: read-only evidence for encryption at rest and the audit log, as the control-plane node shows it.
# Usage: evidence.sh          (the output is pasted unchanged into docs/reports/P2-U6-encryption-audit-evidence.md)
# Nothing is changed. No Secret value is printed: etcd records are shown only as their first 26 bytes (the
# provider prefix) and audit events only as metadata fields.
set -uo pipefail
cd "$(dirname "$0")/../.."

KEY=${KG_LAB_KEY:-$HOME/.ssh/kubeguard-lab}
CONF=${NODES_CONF:-infra/libvirt/nodes.conf}
KEYDIR=${KG_KEY_BACKUP_DIR:-$HOME/.local/share/kubeguard/encryption-keys}
CP=$(grep -v '^[[:space:]]*#' "$CONF" | awk '$2=="control" {print $3; exit}')
node() { ssh -n -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 \
           -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ubuntu@"$CP" "$@"; }
ETCDCTL='id=$(sudo crictl ps --name etcd -q | head -1); sudo crictl exec $id etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key'
LOG=/var/log/kubernetes/audit/audit.log

echo "== date: $(date -Is)"
echo
echo "== API server flags for encryption, audit, authentication and TLS"
node 'pgrep -af "^kube-apiserver" | tr " " "\n" | grep -E "^--(audit|encryption|authentication-config|kubelet-certificate-authority|tls-|profiling|enable-admission|service-account-extend)" | sort'
echo
echo "== Encryption configuration on the node (mode, owner and name only)"
node 'sudo stat -c "%a %U:%G %n" /etc/kubernetes/encryption /etc/kubernetes/encryption/encryption-config.yaml'
echo
echo "== Key copy on the host (mode, owner and name only)"
stat -c '%a %U %n' "$KEYDIR" "$KEYDIR"/*.yaml
echo
echo "== Secrets in etcd, grouped by the first 26 bytes of the stored record (count, prefix)"
node "for key in \$($ETCDCTL get /registry/secrets --prefix --keys-only | grep .); do $ETCDCTL get \$key --print-value-only | head -c 26 | tr -c '[:print:]' '.'; echo; done | sort | uniq -c"
echo
echo "== Audit log files (mode, owner, size, name)"
node "sudo stat -c '%a %U:%G %s %n' $LOG; sudo ls /var/log/kubernetes/audit | wc -l | xargs echo 'files in the directory:'"
echo
echo "== Disk of the control-plane node (df -h /var)"
node "df -h /var"
echo
echo "== Audit events: a Secret read (level Metadata, no request body) and a namespace creation (level Request, body kept)"
node "sudo jq -c 'select(.verb==\"get\" and .objectRef.resource==\"secrets\") | {level, verb, user: .user.username, resource: .objectRef.resource, namespace: .objectRef.namespace, name: .objectRef.name, code: .responseStatus.code, has_request_body: has(\"requestObject\")}' $LOG | tail -n 2"
node "sudo jq -c 'select(.verb==\"create\" and .objectRef.resource==\"namespaces\") | {level, verb, user: .user.username, resource: .objectRef.resource, name: .objectRef.name, code: .responseStatus.code, has_request_body: has(\"requestObject\")}' $LOG | tail -n 2"
echo
echo "== Audit events by level (count, level)"
node "sudo jq -r '.level' $LOG | sort | uniq -c"
