#!/usr/bin/env bash
# P2-U1: install the pinned kubescape CLI into ~/.local/bin and check the SHA256 pinned in infra/versions.env.
# Usage: install-kubescape.sh        (KG_BIN_DIR overrides the target directory)
set -euo pipefail
cd "$(dirname "$0")/../.."
set -a; . infra/versions.env; set +a
DEST=${KG_BIN_DIR:-$HOME/.local/bin}

if [ -x "$DEST/kubescape" ] && env -u KUBECONFIG "$DEST/kubescape" version 2>/dev/null | grep -q "v${KUBESCAPE}\$"; then
  echo "kubescape v$KUBESCAPE is already installed in $DEST"; exit 0
fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/kubescape" "https://github.com/kubescape/kubescape/releases/download/v${KUBESCAPE}/kubescape_${KUBESCAPE}_linux_amd64"
echo "$KUBESCAPE_SHA256  $tmp/kubescape" | sha256sum -c -
mkdir -p "$DEST"
install -m 0755 "$tmp/kubescape" "$DEST/kubescape"
echo "installed kubescape v$KUBESCAPE in $DEST"
