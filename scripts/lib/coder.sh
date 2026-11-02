# shellcheck shell=bash
# Wraps the coder CLI in a detached process session via os.setsid() so it
# cannot open /dev/tty and leak terminal escape sequences into the parent
# shell's input buffer. Source this before any coder invocation.

coder() {
  python3 -c "
import subprocess, os, sys
r = subprocess.run(['coder'] + sys.argv[1:], preexec_fn=os.setsid)
exit(r.returncode)
" "$@"
}

# Coder's LB is internal-only — CODER_URL is a port-forward, not a public
# address. Fail fast with a clear message rather than a cryptic curl/JSON error.
require_coder_reachable() {
  curl -sf --max-time 3 "${CODER_URL}/healthz" &>/dev/null && return 0
  echo "[error] Coder not reachable at ${CODER_URL}" >&2
  echo "[error] Start the control plane's port-forward first, then retry" >&2
  exit 1
}

# Logs in as CODER_ADMIN_EMAIL/CODER_ADMIN_PASSWORD and authenticates the
# coder CLI against CODER_URL. Requires all three to already be set. Sets
# TOKEN in the caller's shell (deliberately not `local`) for scripts that also
# need it for direct API calls the coder CLI doesn't cover.
coder_login() {
  TOKEN=$(curl -sf -X POST "${CODER_URL}/api/v2/users/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${CODER_ADMIN_EMAIL}\",\"password\":\"${CODER_ADMIN_PASSWORD}\"}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['session_token'])")
  coder login "${CODER_URL}" --token "${TOKEN}" &>/dev/null
}
