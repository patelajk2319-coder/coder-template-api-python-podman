#!/usr/bin/env bash
# Provision a developer workspace from the api-python-podman-workspace
# template. The workspace is pre-configured with the IDE, rootless Podman,
# and repo — zero setup for the developer.
# Requires: a reachable, initialised Coder control plane — see README Prerequisites.

set -euo pipefail

export NO_COLOR=1
export TERM=dumb

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
: "${WORKSPACE_REPO:?WORKSPACE_REPO must be set in .env}"

require_coder_reachable

WORKSPACE_NAME="${1:?Usage: workspace.sh <workspace-name>}"

# ── Authenticate ───────────────────────────────────────────────────────────────
coder_login
echo "[info] Authenticated as ${CODER_ADMIN_EMAIL}"

# ── Provision workspace ────────────────────────────────────────────────────────
echo "[----] Provisioning workspace '${WORKSPACE_NAME}' (template: api-python-podman-workspace)..."

# coder create always streams terraform init boilerplate and a resource
# preview table — neither is useful here. Capture it, show it only on
# failure.
BUILD_LOG="$(mktemp)"
trap 'rm -f "${BUILD_LOG}"' EXIT

if coder create "${WORKSPACE_NAME}" \
  --template api-python-podman-workspace \
  --parameter instance_size=medium \
  --parameter repo_url="${WORKSPACE_REPO}" \
  --yes >"${BUILD_LOG}" 2>&1; then
  echo "[info] Workspace '${WORKSPACE_NAME}' created"
else
  echo "[error] Workspace creation failed — full output:" >&2
  cat "${BUILD_LOG}" >&2
  exit 1
fi
