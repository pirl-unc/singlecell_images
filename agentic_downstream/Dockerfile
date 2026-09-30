# agentic_downstream - see README.md for what this image is for, how to build it, and
# the gotchas behind the less obvious steps below.
#
# Thin layer over the image built from Dockerfile.base, which holds the system
# libraries and the full R/Bioconductor stack. This file adds only the fast-moving
# pieces - Node, the agent CLIs, managed settings, entrypoint.sh. See README.md
# "Two-layer build".
#
# Keep in sync with agentic_downstream.def (identical package content). The .def file
# is the actual deliverable - see README.md "Why a .def file" for why.

ARG BASE_IMAGE=benjaminvincentlab/agentic_downstream_base:latest
FROM --platform=linux/amd64 ${BASE_IMAGE}

LABEL org.opencontainers.image.title="agentic_downstream"
LABEL org.opencontainers.image.description="Seurat-free downstream single-cell analysis (SingleCellExperiment, UCell, DESeq2 pseudobulk DE, fgsea, SCPA, speckle/limma, harmony, ComplexHeatmap, survival modelling) plus claude/codex/agy (Antigravity) CLI agents for cluster-based agentic review workflows."
LABEL org.opencontainers.image.source="https://github.com/pirl-unc/singlecell_images"
LABEL org.opencontainers.image.base.name="agentic_downstream_base"
LABEL org.opencontainers.image.vendor="Benjamin Vincent Lab, UNC Lineberger"

# Node.js 20.x LTS via NodeSource. Ubuntu noble's apt `nodejs` (18.x) is old enough to
# risk compatibility issues with the agent CLIs below, which move fast and target
# current Node. curl/gnupg come from the base.
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Agent CLIs. No non-root USER is set: the installed binaries/packages only need
# read+execute at runtime, and this image is designed to run under Singularity/
# Apptainer on the cluster, which maps the container process to the invoking host
# user and binds that user's real $HOME - so per-user config/credential directories
# (~/.claude, ~/.codex, ~/.npm) land in the actual host home directory whether
# credentials come from an interactive OAuth login or from API-key env vars at
# batch-job time.
# codex's native binary is an OPTIONAL dependency that npm silently skips on a failed
# fetch; installing it by name, pinned to the installed codex version, makes that a
# hard error here. See agentic_downstream.def.
RUN npm install -g \
        @anthropic-ai/claude-code \
        @openai/codex && \
    CODEX_VERSION="$(node -p "require('$(npm root -g)/@openai/codex/package.json').version")" && \
    npm install -g "@openai/codex-linux-x64@npm:@openai/codex@${CODEX_VERSION}-linux-x64" && \
    npm cache clean --force

# agy updates itself in place by default; the binary is baked into the image, so
# disable that and rebuild this layer for a new agy. Set before the install so the
# build's own version gate cannot self-update either. See agentic_downstream.def.
ENV AGY_CLI_DISABLE_AUTO_UPDATE=true

# Antigravity CLI (agy) - replaces @google/gemini-cli, which Google no longer serves
# on the "Gemini Code Assist for individuals" tier. Single native binary via Google's
# installer (manifest + SHA-512 check); --dir installs system-wide, and HOME points
# at a throwaway directory because its final step edits shell profiles under $HOME.
RUN curl -fsSL https://antigravity.google/cli/install.sh -o /tmp/agy_install.sh && \
    HOME=/tmp/agy_build_home bash /tmp/agy_install.sh --dir /usr/local/bin && \
    rm -rf /tmp/agy_install.sh /tmp/agy_build_home

# Managed settings: denies rm/rmdir/unlink/shred for Claude Code regardless of
# permission mode, including --dangerously-skip-permissions - managed settings sit
# above every other settings source (project/.claude/settings.json, user
# ~/.claude/settings.json, CLI flags) and nothing at runtime can override a managed
# deny rule. Baked into the read-only image at /etc/claude-code/managed-settings.json,
# so it also can't be edited away at runtime even though the path itself would
# normally just need root to write, not a read-only filesystem.
# CAVEAT (see README.md "Security"): this is a match on the command TEXT Claude
# usually writes, not an OS-level boundary - it stops the normal rm invocation, not
# every conceivable way a subprocess could delete a file. The actual boundary against
# deleting anything outside the intended directory is what's bound writable at the
# Apptainer level (see README.md "Batch use" - don't bind $HOME for batch jobs).
RUN mkdir -p /etc/claude-code && \
    printf '%s\n' \
      '{' \
      '  "permissions": {' \
      '    "deny": [' \
      '      "Bash(rm *)",' \
      '      "Bash(rmdir *)",' \
      '      "Bash(unlink *)",' \
      '      "Bash(shred *)"' \
      '    ]' \
      '  }' \
      '}' \
      > /etc/claude-code/managed-settings.json && \
    chmod 644 /etc/claude-code/managed-settings.json

RUN node --version && npm --version && \
    claude --version && codex --version && agy --version

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Mirrors the .def's %runscript: ENTRYPOINT_OVERRIDE (e.g. a bind-mounted edited
# script, `-v $PWD/entrypoint.sh:/tmp/ep.sh:ro -e ENTRYPOINT_OVERRIDE=/tmp/ep.sh`) runs
# instead of the baked-in copy; unset, the baked-in copy runs. The trailing
# "entrypoint" fills $0 so the container's arguments land in "$@".
ENTRYPOINT ["/bin/bash", "-c", "exec bash \"${ENTRYPOINT_OVERRIDE:-/usr/local/bin/entrypoint.sh}\" \"$@\"", "entrypoint"]
