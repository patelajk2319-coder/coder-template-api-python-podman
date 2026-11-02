#!/usr/bin/env bash
# Registers the already-defined template (templates/api-python-podman-workspace)
# with the Coder control plane via terraform/template-registration (the
# coderd Terraform provider) — this script defines no workspace resources
# itself, it just pushes a new version of an existing template directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/template-registration"

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
: "${CODER_API_TOKEN:?CODER_API_TOKEN must be set in .env — see README Prerequisites}"
: "${TEMPLATE_OWNER:?TEMPLATE_OWNER must be set in .env}"
: "${TEMPLATE_COST_CENTRE:?TEMPLATE_COST_CENTRE must be set in .env}"
: "${TEMPLATE_TEAM:?TEMPLATE_TEAM must be set in .env}"
: "${TEMPLATE_ENV:?TEMPLATE_ENV must be set in .env}"
: "${TEMPLATE_DEFAULT_TTL:?TEMPLATE_DEFAULT_TTL must be set in .env}"
: "${TEMPLATE_ACTIVITY_BUMP:?TEMPLATE_ACTIVITY_BUMP must be set in .env}"

require_coder_reachable

VERSION="$(cat "${ROOT_DIR}/VERSION")"

echo "[----] Pushing api-python-podman-workspace@${VERSION} to ${CODER_URL}..."

# terraform init's own boilerplate (provider-signing notice, "successfully
# initialized") isn't useful here — only show it if init actually fails.
INIT_LOG="$(mktemp)"
trap 'rm -f "${INIT_LOG}"' EXIT
if ! terraform -chdir="${TF_DIR}" init >"${INIT_LOG}" 2>&1; then
  echo "[error] terraform init failed — full output:" >&2
  cat "${INIT_LOG}" >&2
  exit 1
fi

terraform -chdir="${TF_DIR}" apply \
  -var="coder_url=${CODER_URL}" \
  -var="coder_api_token=${CODER_API_TOKEN}" \
  -var="template_version=${VERSION}" \
  -var="template_owner=${TEMPLATE_OWNER}" \
  -var="template_cost_centre=${TEMPLATE_COST_CENTRE}" \
  -var="template_team=${TEMPLATE_TEAM}" \
  -var="template_env=${TEMPLATE_ENV}" \
  -var="template_default_ttl=${TEMPLATE_DEFAULT_TTL}" \
  -var="template_activity_bump=${TEMPLATE_ACTIVITY_BUMP}" \
  -var="provisioner_tag=${PROVISIONER_TAG:-}" \
  -auto-approve

echo ""
echo "[info] api-python-podman-workspace — live"
echo ""
echo "[info] version:     ${VERSION}"
echo "[info] owner:       ${TEMPLATE_OWNER}"
echo "[info] cost-centre: ${TEMPLATE_COST_CENTRE}"
echo "[info] team:        ${TEMPLATE_TEAM}"
echo "[info] env:         ${TEMPLATE_ENV}"
