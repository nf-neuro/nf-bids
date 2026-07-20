#!/usr/bin/env bash
#
# build-docs.sh — build the nf-bids Antora documentation site locally.
#
# Steps:
#   1. Render PlantUML diagram sources (documentation/diagrams/*.puml) to SVG.
#   2. Build the Antora site.
#
# Antora reads content through git. In a normal clone (where .git is a
# directory) it reads the working tree directly, including uncommitted edits,
# so the playbook is used as-is. In a *linked git worktree* (where .git is a
# file) Antora's git layer cannot resolve HEAD, so this script transparently
# snapshots the component into a throwaway git repo and builds from there.
#
# Usage:
#   documentation/bin/build-docs.sh                 # full local build
#   documentation/bin/build-docs.sh --diagrams-only # only render diagrams
#
set -euo pipefail

DOC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${DOC_DIR}/.." && pwd)"
PLANTUML_JAR="${DOC_DIR}/lib/plantuml.jar"
DIAGRAM_SRC="${DOC_DIR}/diagrams"
DIAGRAM_OUT="${DOC_DIR}/modules/ROOT/images/generated"
PLAYBOOK="${DOC_DIR}/antora-playbook.yml"
UI_OVERRIDE_CSS="${DOC_DIR}/ui/site-overrides.css"
UI_OVERRIDE_JS="${DOC_DIR}/ui/site-overrides.js"
GROOVYDOC_OUT="${DOC_DIR}/build/groovydoc"
DIAGRAMS_ONLY=0
# In strict mode (used by CI) missing diagram tooling is a hard error instead
# of a warning, so an incomplete site can never be published silently.
STRICT="${DOCS_STRICT:-0}"
SNAP_DIR=""

[[ "${1:-}" == "--diagrams-only" ]] && DIAGRAMS_ONLY=1

# Single cleanup hook: EXIT fires on success AND on failure under `set -e`,
# unlike a RETURN trap which is skipped when the shell aborts.
cleanup() {
  if [[ -n "${SNAP_DIR}" ]]; then
    rm -rf "${SNAP_DIR}"
  fi
}
trap cleanup EXIT

log() { printf '\033[1;34m[docs]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[docs] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

render_diagrams() {
  mkdir -p "${DIAGRAM_OUT}"
  shopt -s nullglob
  local sources=("${DIAGRAM_SRC}"/*.puml)
  shopt -u nullglob
  if [[ ${#sources[@]} -eq 0 ]]; then
    log "No .puml diagram sources found in ${DIAGRAM_SRC} (nothing to render)."
    return 0
  fi

  # Ensure the PlantUML jar is present (download on demand).
  if [[ ! -f "${PLANTUML_JAR}" ]]; then
    log "PlantUML jar missing; fetching..."
    "${DOC_DIR}/bin/fetch-tools.sh" || true
  fi
  if [[ ! -f "${PLANTUML_JAR}" ]]; then
    local msg="PlantUML jar not available at ${PLANTUML_JAR}; cannot render diagrams."
    [[ "${STRICT}" == "1" ]] && fail "${msg}"
    log "WARNING: ${msg} (skipping; set DOCS_STRICT=1 to make this fatal)"
    return 0
  fi
  # PlantUML needs Graphviz (`dot`) for class/package diagrams.
  if ! command -v dot >/dev/null 2>&1; then
    local msg="Graphviz 'dot' not found on PATH; class/package diagrams will not render."
    [[ "${STRICT}" == "1" ]] && fail "${msg} Install graphviz (e.g. apt-get install graphviz)."
    log "WARNING: ${msg}"
  fi

  log "Rendering ${#sources[@]} PlantUML diagram(s) to SVG..."
  java -jar "${PLANTUML_JAR}" -tsvg -nometadata -o "${DIAGRAM_OUT}" "${DIAGRAM_SRC}"/*.puml
  log "Diagrams rendered to ${DIAGRAM_OUT}"
}

build_site() {
  cd "${DOC_DIR}"
  if [[ "$(git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
    fail "${REPO_ROOT} is not a git working tree."
  fi

  # In strict mode (CI), treat Antora warnings — broken xrefs, missing images,
  # unresolved includes — as build failures so a broken site is never published.
  local antora_args=(--stacktrace)
  if [[ "${STRICT}" == "1" ]]; then
    antora_args+=(--log-failure-level=warn)
  fi
  # CI injects the real GitHub Pages URL so canonical links + the 404 page resolve.
  if [[ -n "${DOCS_SITE_URL:-}" ]]; then
    antora_args+=(--url "${DOCS_SITE_URL}")
  fi

  if [[ -d "${REPO_ROOT}/.git" ]]; then
    # Normal clone: Antora reads the working tree directly.
    log "Building site from working tree (normal git checkout)..."
    npx antora "${antora_args[@]}" "${PLAYBOOK}"
  else
    # Linked worktree (.git is a file): snapshot the component and build.
    log "Linked worktree detected; building from a snapshot repository..."
    SNAP_DIR="$(mktemp -d)"
    # Copy the component, excluding installed/generated artifacts.
    rsync -a --exclude node_modules --exclude build --exclude 'lib/*.jar' \
      "${DOC_DIR}/" "${SNAP_DIR}/documentation/"
    git -C "${SNAP_DIR}" init -q
    git -C "${SNAP_DIR}" -c user.email=docs@local -c user.name=docs \
      add -A >/dev/null
    git -C "${SNAP_DIR}" -c user.email=docs@local -c user.name=docs \
      commit -q -m snapshot >/dev/null
    local snap_playbook="${SNAP_DIR}/documentation/antora-playbook.yml"
    # Repoint the content source at the snapshot repo.
    sed -e "s|url: \.\.|url: ${SNAP_DIR}|" "${PLAYBOOK}" > "${snap_playbook}"
    npx antora "${antora_args[@]}" "${snap_playbook}" \
      --to-dir "${DOC_DIR}/build/site"
  fi
  # mv "${DOC_DIR}/build/site/404.html" "${DOC_DIR}/build/site/nf-bids/404.html"
  # mv "${DOC_DIR}/build/site/index.html" "${DOC_DIR}/build/site/nf-bids/index.html"
  # mv "${DOC_DIR}/build/site/sitemap.xml" "${DOC_DIR}/build/site/nf-bids/sitemap.xml"
  log "Site built at ${DOC_DIR}/build/site/index.html"
}

integrate_api_docs() {
  local version_dir
  version_dir="$(find "${DOC_DIR}/build/site" -mindepth 1 -maxdepth 1 -type d ! -name '_' | head -n1 || true)"
  [[ -n "${version_dir}" ]] || fail "Could not locate built component version directory under build/site/"

  log "Generating GroovyDoc API reference..."
  (cd "${REPO_ROOT}" && ./gradlew groovydoc --no-daemon --console=plain)
  [[ -f "${GROOVYDOC_OUT}/index.html" ]] || fail "GroovyDoc generation failed (missing ${GROOVYDOC_OUT}/index.html)."

  rm -rf "${version_dir}/development/api"
  mkdir -p "${version_dir}/development/api"
  rsync -a "${GROOVYDOC_OUT}/" "${version_dir}/development/api/"
  log "Integrated GroovyDoc at ${version_dir}/development/api/index.html"
}

apply_ui_overrides() {
  local site_css="${DOC_DIR}/build/site/_/css/site.css"
  local site_js="${DOC_DIR}/build/site/_/js/site.js"

  [[ -f "${site_css}" ]] || fail "Missing generated stylesheet: ${site_css}"
  [[ -f "${site_js}" ]] || fail "Missing generated script bundle: ${site_js}"

  if [[ -f "${UI_OVERRIDE_CSS}" ]]; then
    printf '\n\n/* nf-bids local overrides */\n' >> "${site_css}"
    cat "${UI_OVERRIDE_CSS}" >> "${site_css}"
  fi

  if [[ -f "${UI_OVERRIDE_JS}" ]]; then
    printf '\n\n// nf-bids local overrides\n' >> "${site_js}"
    cat "${UI_OVERRIDE_JS}" >> "${site_js}"
  fi

  log "Applied local UI overrides (layout + image behavior)."
}

render_diagrams
[[ "${DIAGRAMS_ONLY}" -eq 1 ]] && exit 0
build_site
integrate_api_docs
apply_ui_overrides
