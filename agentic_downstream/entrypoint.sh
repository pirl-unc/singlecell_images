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

WRAPPER="You are being run as the '${AGENT}' agent in a non-interactive batch job. \
Your task is described in the file '${PROMPT_FILE}' in the current directory (${PROMPT_DIR}) - read it and follow its instructions. \
Unless it tells you to write your output somewhere else, write your complete response to a file named '${RESPONSE_FILE}' in this same directory, \
and when you are completely finished, create an empty marker file named '${RESPONSE_FILE}.done'."

cd "$PROMPT_DIR"

case "$AGENT" in
  claude)
    # CLAUDE_CODE_EFFORT_LEVEL takes precedence over other effort settings
    # for headless (--print) runs. --model is only passed when overridden.
    export CLAUDE_CODE_EFFORT_LEVEL="$AGENT_EFFORT"
    claude_args=(--print)
    [[ -n "$AGENT_MODEL" ]] && claude_args+=(--model "$AGENT_MODEL")
    exec claude "${claude_args[@]}" "$WRAPPER"
    ;;
  codex)
    # --skip-git-repo-check: PROMPT_DIR is an arbitrary bound directory, not
    # necessarily a git repo. --sandbox workspace-write: the response/marker
    # files above must be writable.
    codex_args=(exec --skip-git-repo-check --sandbox workspace-write -c "model_reasoning_effort=\"${AGENT_EFFORT}\"")
    [[ -n "$AGENT_MODEL" ]] && codex_args+=(-m "$AGENT_MODEL")
    exec codex "${codex_args[@]}" "$WRAPPER"
    ;;
  gemini)
    # gemini-cli does not currently expose a stable CLI flag for thinking
    # budget/reasoning effort (tracked upstream; see README.md) - AGENT_EFFORT
    # is accepted for interface consistency with the other two agents but has
    # no effect here yet.
    gemini_args=(-p "$WRAPPER")
    [[ -n "$AGENT_MODEL" ]] && gemini_args+=(-m "$AGENT_MODEL")
    exec gemini "${gemini_args[@]}"
    ;;
esac
