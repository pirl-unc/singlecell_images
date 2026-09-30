#!/usr/bin/env bash
# build.sh - build an agentic_downstream layer with its provenance recorded. Fills the .def
# files' provenance arguments (git commit, uncommitted-changes flag, base image path and
# SHA-256) so they land in the image's labels and in /etc/agentic_downstream/*build_info.
# See README.md "Build" and "Provenance".
#
# Usage:
#   build.sh base  <output.sif>
#   build.sh final <output.sif> <base.sif>
#
# Refuses to:
#   - build from uncommitted changes in this directory (the recorded commit would not be what
#     was built). ALLOW_DIRTY=1 builds anyway and records git_dirty=true.
#   - overwrite an existing output file (image names were reused once, making two different
#     images indistinguishable by filename). Pick a new version, or FORCE=1.
#
# APPTAINER_TMPDIR defaults to /datastore/scratch/users/$USER. Run the base build inside an
# allocation with ample memory (GSVA's byte-compile was OOM-killed once; 32G is plenty).

set -euo pipefail

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 1; }

LAYER="${1:-}"; OUT="${2:-}"; BASE="${3:-}"
case "$LAYER" in
  base)  [[ -n "$OUT" ]] || usage ;;
  final) [[ -n "$OUT" && -n "$BASE" ]] || usage ;;
  *) usage ;;
esac

D="$(cd "$(dirname "$0")" && pwd -P)"
OUT="$(realpath -m "$OUT")"

if [[ -e "$OUT" && "${FORCE:-0}" != "1" ]]; then
  echo "Output already exists: $OUT - choose a new version (or FORCE=1 to overwrite)." >&2
  exit 1
fi

cd "$D"   # %files paths (entrypoint.sh) are relative to the build directory
GIT_SHA="$(git rev-parse HEAD)"
if [[ -n "$(git status --porcelain -- .)" ]]; then
  GIT_DIRTY=true
  if [[ "${ALLOW_DIRTY:-0}" != "1" ]]; then
    echo "Uncommitted changes in $D - commit first, or ALLOW_DIRTY=1 to build anyway:" >&2
    git status --short -- . >&2
    exit 1
  fi
  echo "WARNING: building with uncommitted changes; the image will record git_dirty=true." >&2
else
  GIT_DIRTY=false
fi

args=(--fakeroot --build-arg "GIT_SHA=$GIT_SHA" --build-arg "GIT_DIRTY=$GIT_DIRTY")
if [[ "$LAYER" == final ]]; then
  BASE="$(realpath "$BASE" 2>/dev/null)" || { echo "Base image not found: $3" >&2; exit 1; }
  echo "Hashing base image $BASE ..." >&2
  BASE_SHA256="$(sha256sum "$BASE" | cut -d' ' -f1)"
  args+=(--build-arg "BASE_IMAGE=$BASE" --build-arg "BASE_SHA256=$BASE_SHA256")
  DEF=agentic_downstream.def
else
  DEF=agentic_downstream_base.def
fi

export APPTAINER_TMPDIR="${APPTAINER_TMPDIR:-/datastore/scratch/users/$USER}"
echo "Building $LAYER layer from $DEF at ${GIT_SHA:0:12} (dirty=$GIT_DIRTY) -> $OUT" >&2
apptainer build "${args[@]}" "$OUT" "$DEF"

echo "--- provenance recorded in $OUT:" >&2
apptainer inspect --labels "$OUT" | grep -E 'revision|git_dirty|base_image|base_sha256' >&2 || true
