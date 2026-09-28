#!/usr/bin/env bash
# entrypoint.sh - launch claude/codex/gemini non-interactively against a
# directory of instructions. See ../README.md for the full I/O contract and
# Singularity/Slurm usage examples.
#
# Usage:
#   entrypoint.sh <claude|codex|gemini> <prompt-directory>
#   AGENT=<...> PROMPT_DIR=<...> entrypoint.sh          (positional args win if both given)
#
# For an interactive shell (first-time CLI login, ad hoc work), bypass this
# script entirely:
#   singularity shell --bind "$HOME" image.sif
#   docker run -it --entrypoint bash image
# `singularity shell`/`exec` and Docker's --entrypoint override both ignore
# this script by design, so no interactive branch is needed here.

set -euo pipefail

AGENT="${1:-${AGENT:-}}"
PROMPT_DIR="${2:-${PROMPT_DIR:-}}"

if [[ -z "$AGENT" || -z "$PROMPT_DIR" ]]; then
  echo "Usage: entrypoint.sh <claude|codex|gemini> <prompt-directory>" >&2
  echo "   or: AGENT=<claude|codex|gemini> PROMPT_DIR=<dir> entrypoint.sh" >&2
  exit 1
fi

case "$AGENT" in
  claude|codex|gemini) ;;
  *)
    echo "Unknown agent '$AGENT' - expected claude, codex, or gemini" >&2
    exit 1
    ;;
esac

if [[ ! -d "$PROMPT_DIR" ]]; then
  echo "Prompt directory '$PROMPT_DIR' does not exist" >&2
  exit 1
fi

# I/O convention - overridable per invocation. PROMPT_FILE is a *default* the
# agent is told to look for; RESPONSE_FILE is a *default* the agent is told
# to write to unless PROMPT_FILE itself says otherwise (the agent has file
# tools and will honor a more specific instruction found there, so no bash
# side parsing of PROMPT_FILE is needed here).
PROMPT_FILE="${PROMPT_FILE:-PROMPT.md}"
RESPONSE_FILE="${RESPONSE_FILE:-RESPONSE_${AGENT}.md}"

if [[ ! -f "$PROMPT_DIR/$PROMPT_FILE" ]]; then
  echo "No $PROMPT_FILE found in $PROMPT_DIR" >&2
  exit 1
fi

# Model / reasoning-effort defaults. Left unset (empty) by default so each
# CLI falls back to its own current default model rather than this script
# pinning a model id that goes stale as providers ship new ones. AGENT_EFFORT
# defaults to "high", suited to review/analysis-quality work; override either
# per run.
AGENT_MODEL="${AGENT_MODEL:-}"
AGENT_EFFORT="${AGENT_EFFORT:-high}"

# API keys - accept the standard env var per provider. Codex also recognizes
# CODEX_API_KEY specifically; mirror OPENAI_API_KEY into it if only the
# former is set, so either name works without the caller needing to know
# Codex's naming quirk.
if [[ -n "${OPENAI_API_KEY:-}" && -z "${CODEX_API_KEY:-}" ]]; then
  export CODEX_API_KEY="$OPENAI_API_KEY"
fi

# CONTEXT_DIRS - colon-separated list of additional directories the agent should
# read for context (e.g. the actual project being reviewed), distinct from
# PROMPT_DIR where the prompt/response contract lives. This is documentation for
# the agent, not an access grant: a directory only becomes readable because it was
# --bind mounted into the container (see README.md "Can I bind additional
# directories for read?") - listing it here just tells the agent it exists and is
# in scope, and (for claude) registers it as a first-class working directory via
# --add-dir rather than an incidental read target. Entries that don't exist are
# warned about, not fatal - the caller may have forgotten to --bind one, but the
# primary prompt/response task can still proceed without it.
CONTEXT_DIRS="${CONTEXT_DIRS:-}"
CONTEXT_DIR_LIST=()
if [[ -n "$CONTEXT_DIRS" ]]; then
  IFS=':' read -ra CONTEXT_DIR_LIST <<< "$CONTEXT_DIRS"
fi

CONTEXT_NOTE=""
for d in "${CONTEXT_DIR_LIST[@]}"; do
  if [[ -d "$d" ]]; then
    CONTEXT_NOTE="${CONTEXT_NOTE} ${d}"
  else
    echo "Warning: CONTEXT_DIRS entry '$d' is not a directory - was it --bind mounted? Continuing without it." >&2
  fi
done

WRAPPER="You are being run as the '${AGENT}' agent in a non-interactive batch job. \
Your task is described in the file '${PROMPT_FILE}' in the current directory (${PROMPT_DIR}) - read it and follow its instructions. \
Unless it tells you to write your output somewhere else, write your complete response to a file named '${RESPONSE_FILE}' in this same directory, \
and when you are completely finished, create an empty marker file named '${RESPONSE_FILE}.done'."
if [[ -n "$CONTEXT_NOTE" ]]; then
  WRAPPER="${WRAPPER} Additional context is available, read-only, in the following director(ies): ${CONTEXT_NOTE# }. Do not attempt to modify anything there."
fi

cd "$PROMPT_DIR"

# Permission bypass for all three agents - required because a batch job has no
# human available to click through an approval prompt, and each CLI defaults to
# an interactive-approval posture even in its headless/print mode: without this,
# every CLI reads PROMPT_FILE fine but then refuses to write RESPONSE_FILE. Safe
# here specifically because this is an isolated, single-purpose container - each
# vendor's own docs recommend the equivalent full-bypass flag for exactly that
# case (e.g. Claude Code's docs list `claude -p "<prompt>" --dangerously-skip-permissions`
# under "Run fully unattended inside a container"). See README.md "Gotchas".
case "$AGENT" in
  claude)
    # CLAUDE_CODE_EFFORT_LEVEL takes precedence over other effort settings
    # for headless (--print) runs. --model is only passed when overridden.
    # --dangerously-skip-permissions: --print starts in Manual (read-only) mode
    # by default, which reads PROMPT_FILE fine but blocks writing RESPONSE_FILE.
    export CLAUDE_CODE_EFFORT_LEVEL="$AGENT_EFFORT"
    claude_args=(--print --dangerously-skip-permissions)
    [[ -n "$AGENT_MODEL" ]] && claude_args+=(--model "$AGENT_MODEL")
    for d in "${CONTEXT_DIR_LIST[@]}"; do
      [[ -d "$d" ]] && claude_args+=(--add-dir "$d")
    done
    exec claude "${claude_args[@]}" "$WRAPPER"
    ;;
  codex)
    # --skip-git-repo-check: PROMPT_DIR is an arbitrary bound directory, not
    # necessarily a git repo. --sandbox workspace-write: the response/marker
    # files above must be writable. --ask-for-approval never: workspace-write
    # alone controls what's technically permitted, not whether codex still
    # pauses for human approval before using that permission - never is what
    # actually makes the write happen unattended.
    codex_args=(exec --skip-git-repo-check --sandbox workspace-write --ask-for-approval never -c "model_reasoning_effort=\"${AGENT_EFFORT}\"")
    [[ -n "$AGENT_MODEL" ]] && codex_args+=(-m "$AGENT_MODEL")
    exec codex "${codex_args[@]}" "$WRAPPER"
    ;;
  gemini)
    # gemini-cli does not currently expose a stable CLI flag for thinking
    # budget/reasoning effort (tracked upstream; see README.md) - AGENT_EFFORT
    # is accepted for interface consistency with the other two agents but has
    # no effect here yet. --yolo: bypasses all confirmation prompts (file
    # writes and shell commands both), matching the other two agents' full
    # unattended-in-a-container posture. --approval-mode auto_edit is a
    # narrower alternative if a task only ever needs file reads/writes and
    # never a shell command - see README.md.
    gemini_args=(-p "$WRAPPER" --yolo)
    [[ -n "$AGENT_MODEL" ]] && gemini_args+=(-m "$AGENT_MODEL")
    exec gemini "${gemini_args[@]}"
    ;;
esac
