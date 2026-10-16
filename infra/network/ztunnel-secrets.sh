#!/usr/bin/env bash
# P2-U8: create the key material that Cilium's ztunnel encryption needs and store it as the Secret
# cilium-ztunnel-secrets in kube-system. Run it before "make cilium-install" with ztunnel enabled.
# Usage: ztunnel-secrets.sh        (safe to run again: existing material is kept)
#
# Two key pairs, as in Cilium's own example (examples/kubernetes-ztunnel/generate-secrets.sh, v1.20):
#   bootstrap  secures the connection between ztunnel and the Cilium agent (xDS and certificate server): a
#              self-signed server and client certificate for "localhost", not a CA
#   ca         the root that signs the short-lived workload certificates; a CA certificate
# The files stay on the host in $KG_ZTUNNEL_DIR (default ~/.local/share/kubeguard/ztunnel-ca, directory 700,
# files 600), never in the repository. Nothing secret is printed. The Secret is stored encrypted in etcd (P2-U6).
# If ztunnel rejects these certificates, use Cilium's script instead and create the Secret from its files.
set -euo pipefail
DIR=${KG_ZTUNNEL_DIR:-$HOME/.local/share/kubeguard/ztunnel-ca}
KC=${PROJECT_KUBECONFIG:-$HOME/.kube/kubeguard.kubeconfig}
k() { env -u KUBECONFIG kubectl --kubeconfig "$KC" "$@"; }

umask 077
mkdir -p "$DIR"; chmod 700 "$DIR"

cat > "$DIR/bootstrap.conf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = localhost
[ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = DNS:localhost
EOF
cat > "$DIR/ca.conf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = KubeGuard Cilium ztunnel CA
[ext]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
EOF

made=0
for name in bootstrap ca; do
  if [ ! -f "$DIR/$name-private.key" ] || [ ! -f "$DIR/$name-root.crt" ]; then
    openssl genrsa -out "$DIR/$name-private.key" 2048 2>/dev/null
    openssl req -x509 -new -nodes -key "$DIR/$name-private.key" -sha256 -days 3650 -out "$DIR/$name-root.crt" -config "$DIR/$name.conf"
    made=1
  fi
done
chmod 600 "$DIR"/*
[ $made = 1 ] && echo "created the key material in $DIR" || echo "key material already exists in $DIR"
for name in bootstrap ca; do
  printf '%s certificate: ' "$name"; openssl x509 -in "$DIR/$name-root.crt" -noout -subject -enddate | paste -sd' '
done

# create or update the Secret; the key files go through a pipe and are not shown
k -n kube-system create secret generic cilium-ztunnel-secrets \
  --from-file=bootstrap-private.key="$DIR/bootstrap-private.key" \
  --from-file=bootstrap-root.crt="$DIR/bootstrap-root.crt" \
  --from-file=ca-private.key="$DIR/ca-private.key" \
  --from-file=ca-root.crt="$DIR/ca-root.crt" \
  --dry-run=client -o yaml | k apply -f - >/dev/null
echo "Secret kube-system/cilium-ztunnel-secrets is in place (keys: $(k -n kube-system get secret cilium-ztunnel-secrets -o json | jq -r '.data | keys | join(", ")'))"
