#!/usr/bin/env bash
# Stream startup logs from the active api-python-podman-workspace workspace.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/coder.sh
source "${SCRIPT_DIR}/lib/coder.sh"

if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  echo "[error] .env not found — copy .env.example to .env and fill in values" >&2
  exit 1
fi
set -a
# shellcheck source=/dev/null
source "${ROOT_DIR}/.env"
set +a

: "${CODER_URL:?CODER_URL must be set in .env}"
: "${CODER_ADMIN_EMAIL:?CODER_ADMIN_EMAIL must be set in .env}"
: "${CODER_ADMIN_PASSWORD:?CODER_ADMIN_PASSWORD must be set in .env}"

require_coder_reachable

coder_login

WORKSPACE=$(coder ls --output json 2>/dev/null \
  | python3 -c "
import sys, json
ws = [w['owner_name']+'/'+w['name'] for w in json.load(sys.stdin) if w['template_name']=='api-python-podman-workspace']
print(ws[0]) if ws else (print('[error] No api-python-podman-workspace workspace found', file=sys.stderr) or exit(1))
")

echo "[info] Streaming startup logs for ${WORKSPACE}..."
coder logs "${WORKSPACE}" -f
