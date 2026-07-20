#!/usr/bin/env bash
#
# verify-site.sh — post-build assertion that the documentation site is complete.
#
# Run after `./gradlew docs`. Fails (non-zero exit) if any required generated
# artifact is missing, so CI never publishes a partial or broken site. This is
# the "fail the workflow if any generated artifact is missing/broken/stale"
# guard from the docs platform plan.
#
set -euo pipefail

DOC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_DIR="${DOC_DIR}/build/site"

fail() { printf '\033[1;31m[verify] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[1;32m[verify] OK:\033[0m %s\n' "$*"; }

[[ -d "${SITE_DIR}" ]] || fail "Site directory not found: ${SITE_DIR} (did 'gradlew docs' run?)"

# 1. Landing page.
[[ -f "${SITE_DIR}/index.html" ]] || fail "Missing site landing page: index.html"
ok "landing page present"

# 2. Component start page (versioned path is derived from antora.yml).
component_index="$(find "${SITE_DIR}" -mindepth 2 -maxdepth 2 -name index.html ! -name "_" 2>/dev/null | sort -V | tail -n1 || true)"
[[ -n "${component_index}" ]] || fail "Missing versioned component index under build/site/"
version_dir="$(dirname "${component_index}")"
ok "component index present (${version_dir#${SITE_DIR}/})"

# 3. Rendered diagrams (sources -> SVG). Every .puml must have produced an SVG
#    that actually shipped into the site, and none may contain a render error.
shopt -s nullglob
diagram_sources=("${DOC_DIR}"/diagrams/*.puml)
shopt -u nullglob
[[ ${#diagram_sources[@]} -gt 0 ]] || fail "No PlantUML sources found in diagrams/"
for src in "${diagram_sources[@]}"; do
  name="$(basename "${src}" .puml)"
  svg="$(find "${SITE_DIR}" -name "${name}.svg" 2>/dev/null | head -n1 || true)"
  [[ -n "${svg}" ]] || fail "Diagram '${name}' did not render into the site (${name}.svg missing)"
  if grep -qi "syntax error" "${svg}"; then
    fail "Diagram '${name}' rendered with a PlantUML syntax error"
  fi
done
ok "${#diagram_sources[@]} diagram(s) rendered and shipped"

# 4. Generated API reference (GroovyDoc) integrated into the site.
[[ -f "${version_dir}/development/api/index.html" ]] \
  || fail "Missing generated API reference at ${version_dir#${SITE_DIR}/}/development/api/index.html"
ok "API reference present"

printf '\033[1;32m[verify] Documentation site is complete.\033[0m\n'
