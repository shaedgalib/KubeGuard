#!/usr/bin/env bash
# Acceptance check for P1-U2: run the playbook twice; the second run must change nothing.
# Usage: test-idempotence.sh   (run from anywhere; uses the project virtual environment)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PLAYBOOK=$HERE/../../.venv/bin/ansible-playbook
cd "$HERE"
./gen-inventory.sh >/dev/null
echo "== first run (changes allowed)"
"$PLAYBOOK" site.yml </dev/null 2>&1 | grep -E "PLAY RECAP|ok=" || true
echo "== second run (must report changed=0 and failed=0 on every node)"
out=$("$PLAYBOOK" site.yml </dev/null 2>&1)
recap=$(grep -E "ok=.*changed=.*failed=" <<<"$out")
echo "$recap"
if grep -vq "changed=0" <<<"$recap" || grep -vq "failed=0" <<<"$recap" || grep -vq "unreachable=0" <<<"$recap"; then
  echo "FAIL  the second run changed something or failed"; exit 1
fi
echo "PASS  the second run reports no changes"
