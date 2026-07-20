#!/usr/bin/env bash
set -euo pipefail

DOC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_DIR="${DOC_DIR}/build/site"
DEFAULT_PORT="${DOCS_PORT:-5050}"

log() { printf '\033[1;34m[docs-serve]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[docs-serve] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

is_port_in_use() {
  local port="$1"
  if ! command -v ss >/dev/null 2>&1; then
    return 1
  fi
  ss -ltn "sport = :${port}" | tail -n +2 | grep -q .
}

pick_port() {
  local requested="$1"
  local candidate="${requested}"
  local attempts=0
  while is_port_in_use "${candidate}"; do
    attempts=$((attempts + 1))
    if [[ "${attempts}" -gt 20 ]]; then
      fail "No free port found in range ${requested}-$((requested + 20)); set DOCS_PORT manually."
    fi
    candidate=$((candidate + 1))
  done
  echo "${candidate}"
}

if [[ ! -f "${SITE_DIR}/index.html" ]]; then
  log "Built site missing; running documentation build first..."
  bash "${DOC_DIR}/bin/build-docs.sh"
fi

[[ -f "${SITE_DIR}/index.html" ]] || fail "Missing ${SITE_DIR}/index.html after build."

PORT="$(pick_port "${DEFAULT_PORT}")"
if [[ "${PORT}" != "${DEFAULT_PORT}" ]]; then
  log "Port ${DEFAULT_PORT} is busy; serving on ${PORT} instead."
fi

log "Serving ${SITE_DIR} at http://localhost:${PORT}"
exec npx --yes http-server "${SITE_DIR}" -p "${PORT}" -c-1
