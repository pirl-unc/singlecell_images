#!/usr/bin/env bash
# agentic_run.sh - HOST-side launcher for the agentic_downstream image. Builds the
# `apptainer run` command with the flags that make the container boundary real, so
# they cannot be forgotten. It runs on the host, not in the image: the boundary is
# decided by apptainer before the image starts, so it cannot be baked into the .sif.
# See README.md "Security" and "Batch use".
#
# Usage:
#   agentic_run.sh [options] <claude|codex|agy> <prompt_dir>
#
# Options:
#   -i IMAGE    image to run (default: $AGENTIC_IMG)
#   -c DIR      context directory, bound READ-ONLY and listed in CONTEXT_DIRS (repeatable)
#   -b SRC[:DST[:ro]]
#               extra bind, e.g. a reference folder (repeatable). Declared to the
#               entrypoint's mount check via EXTRA_ALLOWED_MOUNTS.
#   -a          bind ALL agents' credentials (claude, codex, agy) - needed when the
#               agent is an orchestrator that launches the others inside the container.
#               Default: only the running agent's own credentials.
#   -e KEY=VAL  pass an environment variable into the container (repeatable), e.g.
#               -e AGENT_MODEL=<id> -e AGENT_EFFORT=max -e RESPONSE_FILE=review_2.md
#   -o FILE     test an edited entrypoint.sh without a rebuild (ENTRYPOINT_OVERRIDE)
#   -k          pass ANTHROPIC/OPENAI/CODEX/GEMINI API key variables in (via APPTAINERENV_,
#               so never on the command line). Default: not passed, so runs use the stored
#               subscription logins rather than API billing.
#   -M          do NOT mask the credential folders' history (default: masked, see below)
#   -n          dry run: print the apptainer command and exit
#
# Always applied: --cleanenv (the host environment is NOT passed in - only the
# variables below), --no-home, --no-mount hostfs,cwd, the prompt directory bound
# writable, credentials bound individually (never all of $HOME), and all paths
# resolved to their real location (a ~/nate/... symlink path does not exist inside
# the container once hostfs is off).
#
# Credential masking (default; -M turns it off): a credential bind exposes the whole
# folder, and both CLIs keep past sessions, history, memories, skills and caches there.
# For every agent whose credentials are bound, each path listed in masks/<agent>.txt
# (beside this script) is covered by an empty read-only folder or file, or by an empty
# writable folder where the list says "rw"; paths that do not exist on the host are
# skipped. The empty sources are made fresh per run under $AGENTIC_MASK_ROOT (default
# /tmp/agentic_masks_$USER) and declared to the entrypoint's mount check. Lists and the
# 2026-11-21 boundary test: README.md, "What a credential bind also exposes".
#
# Forwarded from the calling shell when set (so `AGENT_MODEL=x agentic_run.sh ...` works
# as well as -e): AGENT_MODEL AGENT_EFFORT AGENT_VERBOSE PROMPT_FILE RESPONSE_FILE
# ALLOW_HOSTFS. Why --cleanenv: the host's TMPDIR (here /datastore/scratch/users/<user>)
# was passed into the container, where - with hostfs off - that path does not exist,
# and `claude --print` exited 0 with no output and no session (found 2026-09-30).
# Any host variable naming a host path can do the same. A clean environment also keeps
# unrelated host secrets away from agents that run with their permission checks off.

set -euo pipefail

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 1; }

IMAGE="${AGENTIC_IMG:-}"
CONTEXT_DIRS_ARG=()
EXTRA_BINDS=()
ALL_CREDS=0
ENV_ARGS=()
OVERRIDE=""
KEEP_KEYS=0
DRY_RUN=0
MASK=1

while getopts ":i:c:b:ae:o:kMnh" opt; do
  case "$opt" in
    i) IMAGE="$OPTARG" ;;
    c) CONTEXT_DIRS_ARG+=("$OPTARG") ;;
    b) EXTRA_BINDS+=("$OPTARG") ;;
    a) ALL_CREDS=1 ;;
    e) ENV_ARGS+=("$OPTARG") ;;
    o) OVERRIDE="$OPTARG" ;;
    k) KEEP_KEYS=1 ;;
    M) MASK=0 ;;
    n) DRY_RUN=1 ;;
    h) usage ;;
    :) echo "Option -$OPTARG needs a value" >&2; usage ;;
    \?) echo "Unknown option -$OPTARG" >&2; usage ;;
  esac
done
shift $((OPTIND - 1))
(( $# == 2 )) || usage

AGENT="$1"
case "$AGENT" in
  claude|codex|agy) ;;
  *) echo "Unknown agent '$AGENT' - expected claude, codex, or agy" >&2; exit 1 ;;
esac

[[ -n "$IMAGE" ]] || { echo "No image: pass -i IMAGE or set AGENTIC_IMG" >&2; exit 1; }
[[ -f "$IMAGE" ]] || { echo "Image not found: $IMAGE" >&2; exit 1; }
IMAGE="$(realpath "$IMAGE")"

PROMPT_DIR="$(realpath "$2" 2>/dev/null)" || { echo "Prompt directory not found: $2" >&2; exit 1; }
[[ -d "$PROMPT_DIR" ]] || { echo "Prompt directory not found: $2" >&2; exit 1; }

args=(run --cleanenv --no-home --no-mount hostfs,cwd --bind "$PROMPT_DIR")

# Credentials: each agent's own paths only, unless -a. claude keeps account state in
# ~/.claude.json beside ~/.claude, so both are needed once hostfs is off.
cred_paths() {
  case "$1" in
    claude) echo "$HOME/.claude" "$HOME/.claude.json" ;;
    codex)  echo "$HOME/.codex" ;;
    agy)    echo "$HOME/.gemini" ;;
  esac
}
cred_agents=("$AGENT")
(( ALL_CREDS )) && cred_agents=(claude codex agy)
for a in "${cred_agents[@]}"; do
  for p in $(cred_paths "$a"); do
    if [[ -e "$p" ]]; then
      args+=(--bind "$p:$p")
    else
      echo "Warning: $p not found - '$a' has no stored login and will fail unless an API key is passed (-k)." >&2
    fi
  done
done

# Mask each listed history/cache path inside the bound credential folders (see header).
mask_allowed=""
if (( MASK )); then
  mask_dir="$(dirname "$(realpath "$0")")/masks"
  mask_root="${AGENTIC_MASK_ROOT:-/tmp/agentic_masks_$USER}"
  run_masks=""
  for a in "${cred_agents[@]}"; do
    list="$mask_dir/$a.txt"
    [[ -f "$list" ]] || { echo "Warning: no mask list $list - '$a' credential folder bound unmasked." >&2; continue; }
    base="$(cred_paths "$a" | awk '{print $1}')"
    [[ -e "$base" ]] || continue
    while read -r rel mode; do
      [[ -z "$rel" || "$rel" == \#* ]] && continue
      target="$base/${rel%/}"
      [[ -e "$target" ]] || continue
      if [[ -z "$run_masks" ]]; then
        if (( DRY_RUN )); then run_masks="$mask_root/<run>"
        else mkdir -p "$mask_root"; run_masks="$(mktemp -d "$mask_root/run_XXXXXX")"; touch "$run_masks/empty_file"; mkdir -p "$run_masks/empty_dir"; fi
      fi
      if [[ "$mode" == "rw" ]]; then
        src="$run_masks/rw_${a}_$(echo "${rel%/}" | tr '/' '_')"
        (( DRY_RUN )) || mkdir -p "$src"
        args+=(--bind "$src:$target")
      elif [[ -d "$target" ]]; then
        args+=(--bind "$run_masks/empty_dir:$target:ro")
      else
        args+=(--bind "$run_masks/empty_file:$target:ro")
      fi
      mask_allowed="${mask_allowed:+$mask_allowed:}$target"
    done < "$list"
  done
fi

context_list=""
for d in "${CONTEXT_DIRS_ARG[@]}"; do
  rd="$(realpath "$d" 2>/dev/null)" || { echo "Context directory not found: $d" >&2; exit 1; }
  [[ -d "$rd" ]] || { echo "Context directory not found: $d" >&2; exit 1; }
  args+=(--bind "$rd:$rd:ro")
  context_list="${context_list:+$context_list:}$rd"
done
[[ -n "$context_list" ]] && args+=(--env "CONTEXT_DIRS=$context_list")

extra_allowed=""
for b in "${EXTRA_BINDS[@]}"; do
  IFS=':' read -r src dst mode <<< "$b"
  rsrc="$(realpath "$src" 2>/dev/null)" || { echo "Bind source not found: $src" >&2; exit 1; }
  dst="${dst:-$rsrc}"
  args+=(--bind "$rsrc:$dst${mode:+:$mode}")
  extra_allowed="${extra_allowed:+$extra_allowed:}$dst"
done
[[ -n "$mask_allowed" ]] && extra_allowed="${extra_allowed:+$extra_allowed:}$mask_allowed"
[[ -n "$extra_allowed" ]] && args+=(--env "EXTRA_ALLOWED_MOUNTS=$extra_allowed")

if [[ -n "$OVERRIDE" ]]; then
  rover="$(realpath "$OVERRIDE" 2>/dev/null)" || { echo "Override script not found: $OVERRIDE" >&2; exit 1; }
  args+=(--bind "$rover:$rover:ro" --env "ENTRYPOINT_OVERRIDE=$rover")
fi

for v in AGENT_MODEL AGENT_EFFORT AGENT_VERBOSE PROMPT_FILE RESPONSE_FILE ALLOW_HOSTFS; do
  [[ -n "${!v:-}" ]] && args+=(--env "$v=${!v}")
done
for kv in "${ENV_ARGS[@]}"; do args+=(--env "$kv"); done   # -e wins: later --env overrides

args+=("$IMAGE" "$AGENT" "$PROMPT_DIR")

if (( DRY_RUN )); then
  printf 'apptainer'; printf ' %q' "${args[@]}"; printf '\n'
  exit 0
fi

# API keys: --cleanenv already keeps them out, so subscription logins are used. With
# -k, hand them over through APPTAINERENV_ (which survives --cleanenv) rather than
# --env KEY=value, which would put the secret on the process command line.
if (( KEEP_KEYS )); then
  for k in ANTHROPIC_API_KEY OPENAI_API_KEY CODEX_API_KEY GEMINI_API_KEY; do
    [[ -n "${!k:-}" ]] && export "APPTAINERENV_${k}=${!k}"
  done
fi

# The launch directory is excluded by --no-mount cwd; start from a neutral one anyway.
cd /tmp
exec apptainer "${args[@]}"
