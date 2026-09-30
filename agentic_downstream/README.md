# agentic_downstream

Seurat-free sibling of [`../singlecell_downstream`](../singlecell_downstream): the same
downstream single-cell analysis package set (SingleCellExperiment, UCell, DESeq2
pseudobulk DE, fgsea, SCPA, speckle/limma composition testing, harmony integration,
ComplexHeatmap, survival modelling), but built on `bioconductor/bioconductor_docker`
instead of `satijalab/seurat` - no `Seurat`/`SeuratObject`, and none of the Seurat-only
dependency tree (`spatstat.*`, `sctransform`, `leiden`, `hdf5r`, `RcppAnnoy`,
`RcppHNSW`) that came along for free with that base image. SingleCellExperiment is the
object model here, not Seurat.

**Base:** `bioconductor/bioconductor_docker:RELEASE_3_20` - R 4.4.2, Ubuntu 24.04
noble (verified by inspection, see "Gotchas" below), with a Posit-backed binary CRAN
repo already pointed at `__linux__/noble`.

It also bundles the `claude`, `codex`, and `agy` (Google Antigravity) CLI agents (plus
Node.js) so it can
run as an agentic review environment on the cluster via Apptainer + Slurm: an
interactive `claude` session can act as a "manager" iterating on an R analysis plan,
and spin up one-shot `codex`/`agy` batch jobs pointed at a shared bound directory to
get a technical review, repeating until satisfied.

## What's different from `singlecell_downstream`

| | singlecell_downstream | agentic_downstream |
|---|---|---|
| Base image | `satijalab/seurat:5.4.0` | `bioconductor/bioconductor_docker:RELEASE_3_20` |
| Seurat / SeuratObject | included | **not included** |
| Object model | Seurat + SCE | SCE only |
| Agent CLIs | none | claude, codex, agy + Node |
| Binary CRAN repo | configured manually (base doesn't ship one) | ships preconfigured on `__linux__/noble` |

If you're porting an analysis script from `singlecell_downstream` to this image, check
it for direct `Seurat::` calls first - those need an SCE-based equivalent, since Seurat
itself isn't here to fall back on.

## Files

- `agentic_downstream_base.def` - Apptainer definition for the **base layer**: system
  libraries and the full R/Bioconductor stack. Slow (an hour or more), rarely rebuilt.
- `agentic_downstream.def` - Apptainer definition for the **final image**, built on top
  of the base `.sif`: Node, the agent CLIs, managed settings, `entrypoint.sh`. Minutes.
- `Dockerfile.base` / `Dockerfile` - equivalent Docker recipes for the same two layers,
  kept as a portable record
- `agentic_run.sh` - **host-side** launcher: builds the `apptainer run` command with the
  flags that make the container boundary real (see "Batch use" and "Security"). Not
  part of the image; changing it needs no rebuild.
- `build.sh` - builds either layer with its provenance recorded (see "Build", "Provenance")
- `entrypoint.sh` - the batch-job launcher; copied into the final image (`%files` in the
  `.def`, `COPY` in the Dockerfile) and invoked by its `%runscript`/`ENTRYPOINT`

Each `.def` and its Dockerfile are identical in package content. **Change both
together.** See "Two-layer build" below for which layer a given change belongs in.

## Why a `.def` file

Same reason as `../singlecell_downstream`: the deliverable is a `.sif` for a
Singularity/Apptainer HPC cluster. Building the Docker image on an arm64 Mac means
emulating linux/amd64 under QEMU, which in that image's build produced repeated
non-deterministic failures - `g++` segfaulting mid-compile, an internal compiler
error, a `BrokenPipeError` in an apt post-install script - none of them code problems,
just the emulator crashing on a different package each attempt. Building with
Apptainer on a native x86_64 host removes that entire class and emits the `.sif`
directly. The Dockerfile remains for anyone who wants a Docker image on amd64
hardware.

## Build

Use **`build.sh`**, on a native **x86_64** host with Apptainer 1.2+ (for `--build-arg`). It
records where the image came from (see "Provenance"), refuses to build from uncommitted changes,
and refuses to overwrite an existing image file. Commit first, then build the base, but only when
it doesn't exist yet or the R stack changed. Run the base build inside an allocation with ample
memory (GSVA's byte-compile was OOM-killed once; 32G is plenty):

```bash
./build.sh base  /datastore/scratch/users/$USER/agentic_downstream_base_<base_version>.sif
```

Then the final image on top of that base (minutes):

```bash
./build.sh final /datastore/scratch/users/$USER/agentic_downstream_<version>.sif \
                 /path/to/agentic_downstream_base_<base_version>.sif
```

`ALLOW_DIRTY=1` builds from uncommitted changes anyway (recorded as `git_dirty=true`); `FORCE=1`
overwrites an existing output. **Give every build a new version**: reusing a name makes two
different images indistinguishable by filename, as happened once with `0.0.3`.

`--fakeroot` works without an `/etc/subuid` entry - Apptainer falls back to a root-mapped user
namespace, sufficient for `apt-get install`/`npm install -g` on a glibc base. Build into scratch,
then move each `.sif` to its final directory. **Keep the base `.sif`** - deleting it means the
next CLI or entrypoint change costs the full hour again.

The raw `apptainer build` commands still work (`--build-arg BASE_IMAGE=...` for the final layer);
the provenance fields are then recorded as `unknown`.

Docker equivalent, if building on amd64 hardware:

```bash
docker build --platform linux/amd64 -f Dockerfile.base \
  --build-arg GIT_SHA=$(git rev-parse HEAD) --build-arg GIT_DIRTY=false \
  -t benjaminvincentlab/agentic_downstream_base:<base_version> .
docker build --platform linux/amd64 \
  --build-arg BASE_IMAGE=benjaminvincentlab/agentic_downstream_base:<base_version> \
  --build-arg GIT_SHA=$(git rev-parse HEAD) --build-arg GIT_DIRTY=false \
  -t benjaminvincentlab/agentic_downstream:<version> .
```

### Provenance

Each image records the commit it was built from, because the agent CLIs are unpinned: two builds
of the same commit can contain different claude/codex/agy versions, and those versions change
behaviour (codex 0.158 → 0.159 changed which flags it accepts). Recorded:

| Where | What |
|---|---|
| Labels (`apptainer inspect --labels <image>`) | `org.opencontainers.image.revision` (commit), `agentic_downstream.git_dirty`, and for the final layer `agentic_downstream.base_image` + `agentic_downstream.base_sha256` |
| `/etc/agentic_downstream/build_info` (final layer) | commit, dirty flag, base image path and SHA-256, build time (UTC), claude / codex / agy / node versions |
| `/etc/agentic_downstream/base_build_info` (base layer, inherited) | commit, dirty flag, build time, R and Bioconductor versions |
| Every run's log | `entrypoint.sh` prints one line - commit, build time and CLI versions - before starting the agent |

```bash
apptainer inspect --labels <image> | grep -E 'revision|git_dirty|base_'
apptainer exec <image> cat /etc/agentic_downstream/build_info /etc/agentic_downstream/base_build_info
```

Images built before this was added (0.0.3 and earlier) have none of it; `entrypoint.sh` says so.

### Two-layer build

The R/Bioconductor install is well over an hour and changes rarely; the agent CLIs and
`entrypoint.sh` change often. Apptainer has no layer caching - `%post` is one shell block
that re-runs from scratch on every build - so in a single `.def` any edit to
`entrypoint.sh`, or just picking up a new `claude`/`codex`/`agy` release, cost a
full R rebuild. Splitting the image keeps those changes to a few minutes.

| Change | Rebuild |
|---|---|
| `entrypoint.sh`, agent CLI versions, managed settings, Node | final image only |
| R/Bioconductor/CRAN/GitHub package set, system libraries, base image tag | base, then final |
| Testing an `entrypoint.sh` edit | neither - see below |

Version the two independently: a final image records which base it was built from in
the `--build-arg` you passed, so note that alongside the final image's version.

⚠ A derived Apptainer image's `%environment` **replaces** the base's rather than
extending it, which is why `R_LIBS_USER` appears in both `.def` files. Keep them
identical (see "Gotchas", host personal R library). Docker `ENV` *is* inherited, so the
Dockerfile pair sets it only in `Dockerfile.base`.

### Testing an entrypoint change

No rebuild needed. `%runscript` runs `$ENTRYPOINT_OVERRIDE` if set, falling back to the
baked-in `/usr/local/bin/entrypoint.sh` otherwise. `agentic_run.sh -o` binds the edited
script in and points at it:

```bash
./agentic_run.sh -i <image> -o ./entrypoint.sh claude /path/to/prompt_dir

# raw equivalent
apptainer run --cleanenv --no-home --no-mount hostfs,cwd --bind /path/to/prompt_dir \
  --bind "$HOME/.claude:$HOME/.claude" --bind "$HOME/.claude.json:$HOME/.claude.json" \
  --bind /path/to/entrypoint.sh:/path/to/entrypoint.sh:ro \
  --env ENTRYPOINT_OVERRIDE=/path/to/entrypoint.sh \
  <image> claude /path/to/prompt_dir
```

It is invoked via `bash`, so the bound file needs no execute bit. Once it works, rebuild
the final image to bake it in - an override is for testing, not for production runs.

For an image built **before** `ENTRYPOINT_OVERRIDE` existed, bind the edited script
directly over the baked-in path instead; this works on any build:

```bash
--bind /path/to/entrypoint.sh:/usr/local/bin/entrypoint.sh:ro
```

Docker: `-v "$PWD/entrypoint.sh:/tmp/ep.sh:ro" -e ENTRYPOINT_OVERRIDE=/tmp/ep.sh`.

### Iterating on a failed build

`%post` is a single shell block with no layer caching, so a failure restarts it. To
test a fix against an existing image without a full rebuild:

```bash
mkdir -p /tmp/testlib
apptainer exec --bind /tmp/testlib:/testlib <image>.sif Rscript -e \
  ".libPaths(c('/testlib', .libPaths())); BiocManager::install('<pkg>', lib='/testlib', force=TRUE); library(<pkg>, lib.loc='/testlib')"
```

For an agent-CLI fix, `apptainer shell` into the image and try `npm install -g` /
`claude --version` etc. directly before committing a change to the `.def`.
`--writable-tmpfs` alone does **not** make `/usr/local/lib/R/site-library` (or npm's
global prefix) writable.

## Verify

Each build runs its own gate automatically - R packages in the base build, agent CLI
versions in the final build - and `%test` is re-runnable on either:

```bash
apptainer test agentic_downstream_base_<base_version>.sif   # full per-package R check
apptainer test agentic_downstream_<version>.sif             # base came through + CLIs run
```

A base pass prints a per-package `OK` list and the R/Bioc version line (the build
itself prints `all N required packages present and loadable`). A final-image pass
prints the R/Bioc version line and each CLI's `--version` output. The final image's R
stack is the base layer unchanged, so it does not repeat the full package check.

## Interactive use (login, ad hoc work)

`%runscript` (what `apptainer run` invokes) expects an agent name + directory - see
"Batch use" below. For interactive use, including the one-time login each CLI needs
before it can run on a subscription, bypass it with `apptainer shell`, which ignores
`%runscript` by design.

**Log in from a shell that sees only that agent's credential location**, the same view
a batch run will have. A login made from a shell that can see all of `$HOME` (plain
`apptainer shell`, or any launch while the site's hostfs mounts are on - see
"Security") can save its token somewhere a restricted batch run cannot see.

```bash
# claude (then /login)             codex (then codex login --device-auth)
apptainer shell --cleanenv --no-home --no-mount hostfs,cwd \
  --bind "$HOME/.claude:$HOME/.claude" --bind "$HOME/.claude.json:$HOME/.claude.json" <image>
apptainer shell --cleanenv --no-home --no-mount hostfs,cwd --bind "$HOME/.codex:$HOME/.codex" <image>

# agy (then run `agy`, open the printed URL, paste the code back)
apptainer shell --cleanenv --no-home --no-mount hostfs,cwd --bind "$HOME/.gemini:$HOME/.gemini" <image>

# Docker equivalent
docker run -it --entrypoint bash benjaminvincentlab/agentic_downstream:<version>
```

Create any credential path that does not exist yet before binding it
(`mkdir -p ~/.codex ~/.gemini ~/.claude; touch ~/.claude.json`). Apptainer runs the
container as the invoking user, so credentials land in your real home directory and
persist across runs. Add `--bind /some/work/dir --pwd /some/work/dir` for ad hoc work in
a particular folder.

## Batch use (the plan-review workflow)

**Use `agentic_run.sh`** (in this directory, runs on the host). It always adds the
launch flags that make the container boundary real - `--no-home --no-mount hostfs,cwd`
(see "Security") - binds only the running agent's credentials, binds context
directories read-only, resolves symlinked paths such as `~/nate/...` to their real
location, and unsets API key variables so subscription logins are used.

```bash
export AGENTIC_IMG=/path/to/benjaminvincentlab-agentic-downstream-<version>.img

./agentic_run.sh claude /path/to/prompt_dir
./agentic_run.sh -c /path/to/project codex /path/to/prompt_dir          # + read-only context
./agentic_run.sh -e AGENT_MODEL=<id> -e AGENT_EFFORT=max agy /path/to/prompt_dir
./agentic_run.sh -a -c /path/to/project claude /path/to/prompt_dir     # orchestrator: all creds
./agentic_run.sh -n codex /path/to/prompt_dir                          # print the command only
```

Options: `-c DIR` context (read-only, repeatable), `-b SRC[:DST[:ro]]` extra bind,
`-a` bind every agent's credentials (for an in-container orchestrator that launches the
others), `-e KEY=VAL` pass a variable in, `-o FILE` test an edited `entrypoint.sh`,
`-k` keep API key variables, `-n` dry run. `./agentic_run.sh -h` prints the full usage.

The raw command it builds, for when the script is not available:

```bash
apptainer run --cleanenv --no-home --no-mount hostfs,cwd \
  --bind /path/to/prompt_dir \
  --bind "$HOME/.codex:$HOME/.codex" \
  --bind /path/to/project:/path/to/project:ro --env CONTEXT_DIRS=/path/to/project \
  <image> codex /path/to/prompt_dir
```

**`entrypoint.sh` refuses to start an agent if the launch flags were missed.** It
checks `/proc/mounts` for network filesystems the run did not declare (the prompt
directory, `CONTEXT_DIRS`, the credential paths, `EXTRA_ALLOWED_MOUNTS`) and exits with
`REFUSING TO RUN` and the list of exposed mounts - which is what a launch without
`--no-mount hostfs` produces on this cluster. `ALLOW_HOSTFS=1` skips the check for a
deliberate exception. A passing check is inherited by nested calls, so an in-container
orchestrator can call `entrypoint.sh` again for sub-agents. It is a guard against a
forgotten flag, not against a hostile agent.

Example `sbatch` script for a codex review job:

```bash
#!/bin/bash
#SBATCH --job-name=codex-review
#SBATCH --time=00:30:00
#SBATCH --mem=4G

/path/to/agentic_run.sh -i /path/to/<image> codex /proj/shared/plan_review
```

### Env var passthrough caveat

Unlike Docker, Apptainer passes host environment variables through to the container
**by default**. If a job uses `--cleanenv` (common in shared-cluster Slurm setups to
avoid leaking unrelated environment into jobs), that passthrough is disabled and env
vars must instead be prefixed `APPTAINERENV_` (or `SINGULARITYENV_` on older
Singularity installs), e.g.:

```bash
APPTAINERENV_OPENAI_API_KEY="$OPENAI_API_KEY" \
  apptainer run --cleanenv --no-home --no-mount hostfs,cwd --bind /proj/shared/plan_review \
  <image> codex /proj/shared/plan_review
```

Check whether your Slurm job template uses `--cleanenv` before assuming a bare
`export` in the submitting shell is enough.

### API keys

| Agent | Env var |
|---|---|
| claude | `ANTHROPIC_API_KEY` |
| codex | `OPENAI_API_KEY` (mirrored to `CODEX_API_KEY` automatically by `entrypoint.sh` if only `OPENAI_API_KEY` is set) |
| agy | `GEMINI_API_KEY` - **and** `"modelProvider": "gemini"` in `~/.gemini/antigravity-cli/settings.json`; per Google's docs either alone has no effect |

API keys bill the provider's API. Batch runs can use a stored subscription login
instead, see below. `agentic_run.sh` unsets all four key variables unless given `-k`.

Never pass a key as `--env KEY="$KEY"`: the shell expands it onto the command line,
where other users on a shared node can read it from `ps` / `/proc/<pid>/cmdline`. Keep
it in a `chmod 600` file, `export KEY="$(< file)"` in the submitting shell, and let
Apptainer's default environment passthrough carry it in (or use `--env-file`).

### Subscription login for batch runs

To bill a ChatGPT / Claude / Google AI subscription rather than the API, log in once
from a restricted shell (see "Interactive use"), then bind **only** that agent's
credential location into batch runs - which `agentic_run.sh` does by default.

| Agent | Log in with | Credential location to bind |
|---|---|---|
| claude | `/login` in an interactive `claude` | `~/.claude` **and** `~/.claude.json` |
| codex | `codex login --device-auth` (the browser-callback login cannot complete on a headless node) | `~/.codex` |
| agy | run `agy`, open the printed URL, paste the code back | `~/.gemini` |

- **Unset the API key variables.** Host env passes through by default and
  `entrypoint.sh` mirrors `OPENAI_API_KEY` into `CODEX_API_KEY`; a key that is present
  is expected to take precedence over the stored login and bill the API.
- **Bind credential paths writable**, not `:ro` - the CLIs refresh tokens in place.
- **The agent can read that token.** It runs with a full permission bypass, so this is
  the cost of subscription auth; binding one agent's credentials rather than `$HOME`
  keeps it to that one.
- **Check a login the way batch will use it**, e.g. for agy:
  `apptainer exec --cleanenv --no-home --no-mount hostfs,cwd --bind "$HOME/.gemini:$HOME/.gemini" <image> agy --dangerously-skip-permissions -p "Reply only OK."`
  should print `OK`; a login URL means the token is not in the bound location.
- **agy** prefers the OS keyring (D-Bus Secret Service), which does not exist inside the
  container; it falls back to file storage under `~/.gemini` (`Using file-based token
  storage because %s detected`). **Unverified** that the token lands in `~/.gemini`:
  every login made while developing this image ran with the site's hostfs mounts on, so
  it could see all of `$HOME`. Run the check above before relying on agy in batch.
- **agy is not gemini-cli.** `@google/gemini-cli` was removed from this image because
  Google stopped serving it on the "Gemini Code Assist for individuals" tier (login
  fails with `This client is no longer supported ... migrate to the Antigravity suite`).
  Old `~/.gemini` contents from gemini-cli are migrated by agy on first run.

### I/O convention

By default, `entrypoint.sh`:
1. Looks for `PROMPT.md` in the bound directory (override the filename with the
   `PROMPT_FILE` env var).
2. Instructs the agent to write its complete response to `RESPONSE_<agent>.md` in that
   same directory (override with `RESPONSE_FILE`), and to create an empty
   `RESPONSE_<agent>.md.done` marker file when finished.

This is conveyed to the agent as an instruction, not enforced by the script - all
three CLIs are themselves agentic with file read/write tools, so if `PROMPT.md`
explicitly says "write your findings to `foo.md` instead," the agent will follow that
more specific instruction. A manager `claude` session can poll the shared directory
for `RESPONSE_<agent>.md.done` to know a review has landed, without needing to track
Slurm job state directly.

### Additional context directories (reviewing a separate project)

A review task often needs to read the actual project being reviewed, not just the
`PROMPT.md`/`RESPONSE_<agent>.md` pair in the prompt directory. Bind the project
directory **read-only** alongside the prompt directory, and list it in `CONTEXT_DIRS`
(colon-separated, PATH-style) so the entrypoint tells the agent it exists and is in
scope:

```bash
./agentic_run.sh -c /path/to/project claude /path/to/review_dir
./agentic_run.sh -c /path/to/project -c /path/to/shared/docs claude /path/to/review_dir

# raw equivalent: bind each read-only AND list it, colon-separated
apptainer run --cleanenv --no-home --no-mount hostfs,cwd --bind /path/to/review_dir \
  --bind "$HOME/.claude:$HOME/.claude" --bind "$HOME/.claude.json:$HOME/.claude.json" \
  --bind /path/to/project:/path/to/project:ro --env CONTEXT_DIRS=/path/to/project \
  <image> claude /path/to/review_dir
```

`CONTEXT_DIRS` is documentation for the agent, not an access grant on its own - a
directory is only actually readable because it was `--bind` mounted (with `:ro` so
review access can't become write/delete access too; see "Security" above for why the
mount, not the CLI's cooperation, is the boundary that matters). Listing it in
`CONTEXT_DIRS` just makes the agent aware of it: for claude, `entrypoint.sh` passes
each entry as `--add-dir` (agy likewise, one `--add-dir` per entry), registering it as
a first-class working directory rather than an incidental read target; for codex, which
has no equivalent flag, the wrapper instruction mentions the paths directly instead. An entry that isn't
actually a directory (e.g. the bind was forgotten) gets a warning on stderr and is
skipped rather than failing the whole run.

Without `CONTEXT_DIRS` set at all, nothing changes from before - the agent only knows
about `PROMPT_DIR` unless `PROMPT.md` itself names another path (which still only
works if that path was bound).

### Model and reasoning-effort defaults

| Env var | Default | Effect |
|---|---|---|
| `AGENT_MODEL` | unset (CLI's own default) | Passed as `--model`/`-m` to whichever agent runs. Left unset by default deliberately - pinning a specific model id here would go stale as providers ship new models faster than this file gets updated. |
| `AGENT_EFFORT` | `high` | claude: exported as `CLAUDE_CODE_EFFORT_LEVEL` (`low`/`medium`/`high`/`xhigh`/`max`). codex: passed as `-c model_reasoning_effort="..."` (`low`/`medium`/`high`, plus `xhigh` in some SDK contexts). agy: passed as `--effort` (`low`/`medium`/`high`/`max` - no `xhigh`, which agy will reject). |

## Security

Unattended runs give each agent CLI a full permission bypass (claude and agy
`--dangerously-skip-permissions`, codex `--dangerously-bypass-approvals-and-sandbox` -
see `entrypoint.sh`), because no human is there to answer an approval prompt. The CLIs'
own guardrails are therefore almost entirely off, and **the only real boundary is what
the container can see.** That boundary is set on the `apptainer` command line, on the
host, before the image runs - it cannot be built into the image or enforced by
`entrypoint.sh`.

### The launch flags that make the boundary real

```bash
apptainer run --cleanenv --no-home --no-mount hostfs,cwd \
  --bind "$HOME/.<agent>:$HOME/.<agent>" \
  --bind /path/to/prompt_dir \
  --bind /path/to/context:/path/to/context:ro \
  <image> <agent> /path/to/prompt_dir
```

| Flag | Without it |
|---|---|
| `--no-mount hostfs` | **Every host network filesystem is mounted read-write** if the site config sets `mount hostfs = yes` - see below. |
| `--no-mount cwd` | The directory you launched from is bound in, silently widening access (and, for claude, loading any `CLAUDE.md` found there). |
| `--no-home` | Your whole home directory is bound in (Apptainer's default). |
| `:ro` on context binds | The agent can modify the project it was only meant to read. |

`agentic_run.sh` builds exactly this command, and `entrypoint.sh` refuses to start an
agent when undeclared network filesystems are mounted (see "Batch use").

Then bind back only what the run needs: the prompt directory (writable), context
directories (read-only), and each agent's credential location (see "Subscription login
for batch runs"). An agent can read any token bound into its container - that is the
cost of subscription auth, and why only credential paths, never all of `$HOME`, are bound.

### Why `--no-mount hostfs`: `--no-home` and `--bind` alone are not a boundary here

The UNC LBG cluster's `/etc/apptainer/apptainer.conf` sets **`mount hostfs = yes`**:
Apptainer mounts every host network filesystem into every container, read-write,
regardless of `--bind` or `--no-home`. Measured 2026-09-30 inside a
`--no-home --cleanenv` container on image 0.0.3:

- `/home/<user>` was fully visible and writable (it is its own NFS mount, so hostfs mounts
  it even though `--no-home` skips the default home bind);
- all of `/datastore` was visible and writable - every project, every lab's share, raw
  data included;
- `--containall` hid `$HOME` but still left `/datastore` visible.

So **every run launched without `--no-mount hostfs` - which included all runs made while
this image was being developed - had full read/write access to `/datastore` and the
home directory**, with the agent's permission checks off. With
`--no-mount hostfs,cwd`, the same container sees only its bound paths: `$HOME` contains
only the bound credential directory, the rest of the project tree is absent, and a
`:ro`-bound context directory refuses writes (`Read-only file system`).

Check your own site before trusting any bind-only setup:
```bash
grep -nE '^\s*mount (hostfs|home)' /etc/apptainer/apptainer.conf
apptainer exec --cleanenv --no-home --no-mount hostfs,cwd --bind /path/to/prompt_dir <image> \
  bash -c 'ls -A $HOME; ls /datastore 2>&1'   # expect: empty $HOME, no /datastore listing
```

Side effects of turning hostfs off:
- **claude also needs `--bind "$HOME/.claude.json:$HOME/.claude.json"`** (account state
  lives beside `~/.claude`, not in it). Runs without hostfs that bind only `~/.claude`
  may report not being logged in.
- **A login done while hostfs was on may have been saved outside the credential
  directory you now bind.** Re-check each agent with only its own directory bound, and
  log in again from a restricted shell if it asks.
- Paths like `~/nate/...` that reach `/datastore` through a symlink in your home no
  longer resolve. Use the real `/datastore/...` path in binds and arguments.
- `/tmp` is still the host's (`mount tmp = yes`); use `--contain` if that matters.

### Inner layers - defense in depth only

**Claude: managed deny rule.** `/etc/claude-code/managed-settings.json` (baked in at
build time) denies `Bash(rm *)`, `Bash(rmdir *)`, `Bash(unlink *)` and `Bash(shred *)`.
Managed settings outrank every other settings source, `--dangerously-skip-permissions`
included. It is a match on command *text*, not an OS-level control - a script calling
`os.remove()` is not caught - so it stops the ordinary case only. It also means a Claude
orchestrator inside the image cannot delete files, so pipelines must version outputs
rather than clean up.

**Claude: critical-path protection.** Recursive removal of `/`, a top-level directory,
the home directory, or the working directory and its parents is never auto-approved,
even under bypass. **Unverified** what this does in non-interactive `--print` mode,
where there is no terminal to ask.

**codex: no working sandbox inside Apptainer.** codex's `--sandbox workspace-write`
would be a real OS-level control, but it is built on bubblewrap, which cannot create its
mount namespace inside an Apptainer container: every command *and* file write fails
with `bwrap: Can't bind mount /oldroot/ on /newroot/: Unable to mount source on
destination: Invalid argument` (reproduced on codex-cli 0.158 under default, `--userns`
and `--fakeroot`, via `codex sandbox linux -- echo`). `entrypoint.sh` therefore runs
codex with `--dangerously-bypass-approvals-and-sandbox`. (`Codex could not find
bubblewrap on PATH` is a separate, harmless warning: codex falls back to a bundled
copy, which then fails for the reason above.)

**agy: none in use.** agy has a `--sandbox` flag ("terminal restrictions"), but its
mechanism is undocumented and untested inside Apptainer, so `entrypoint.sh` does not
pass it, and agy has no managed deny rule. For codex and agy, the launch flags above are
the *only* protection.

**All agents in one container share everything.** An in-container orchestrator that
calls the other agents as child processes gives each of them the orchestrator's full
view - every bound path and every bound credential. Isolating one agent's view from
another's requires separate containers.

### Before trusting unattended runs

Test with a deliberately adversarial `PROMPT.md` against each agent, launched with the
flags above: delete `PROMPT.md`, list and read files in `$HOME`, write into a `:ro`
context directory, read a `/datastore` path that was not bound, write to `/etc`.
Confirm each fails cleanly rather than succeeding or hanging.

## Gotchas

Recorded because each one cost a build cycle on `../singlecell_downstream`, and this
image installs much of the same package chain, so the same failure modes apply here.

**Posit binary repos are distro-specific and fail silently.** Unlike
`satijalab/seurat`, `bioconductor/bioconductor_docker:RELEASE_3_20` ships a binary
CRAN repo already configured (`p3m.dev/cran/__linux__/noble/...`) - confirmed by
inspection:

```bash
docker run --rm --platform linux/amd64 bioconductor/bioconductor_docker:RELEASE_3_20 \
  bash -c 'cat /etc/os-release | head -3; R --version | head -1; Rscript -e "options(\"repos\")"'
```

If the base image tag ever changes, re-run this before trusting anything downstream -
a wrong codename doesn't error, P3M just serves source packages instead of binaries,
and a build that should take minutes compiles for hours.

**R package install failures are warnings, not errors.** `install.packages()` and
`install_local()` return normally after a failed install, so `Rscript` exits 0 and
`set -e` never fires. Hence the explicit `requireNamespace()` gate at the end of
`%post`, mirrored here for the R stack and extended to a plain version-check gate for
the agent CLIs (a broken `npm install -g` would otherwise only surface the first time
someone tries to launch an agent).

**A failing `%test` does not fail an Apptainer build.** It writes the `.sif` and
exits 0 regardless. Anything that must gate the build belongs in `%post` - true for
both the R gate and the CLI version checks.

**The base image ships R packages whose system libraries are absent.** Two bite,
identical to `../singlecell_downstream`:

- `SpatialExperiment` imports `magick`, so `libmagick++-6.q16-9t64` is required even
  though nothing here uses ImageMagick directly - pulled in transitively through
  GSVA/clustermole/SCPA. Install the runtime package, not `-dev`.
- `Rhdf5lib` is compiled against a system szip that isn't installed
  (`libsz.so.2: cannot open shared object file`). GSVA reaches it via the
  DelayedArray/HDF5Array chain. Fixed by force-reinstalling `Rhdf5lib`, `rhdf5`, and
  `HDF5Array` from source so they link their own bundled HDF5.

**GitHub installs.** `remotes::install_github()` resolves refs through
`api.github.com`, rate limited to 60 unauthenticated calls/hour/IP, and R's
`download.file()` couldn't reach GitHub from inside the build at all in prior
attempts. Fetch with `curl` from `codeload.github.com` and `install_local()` instead,
pinned to commit SHAs.

**Install order matters for SCPA.** It needs `clustermole` and `ComplexHeatmap`
present first, and `clustermole` needs Bioconductor packages that
`install.packages()` won't fetch because `getOption("repos")` is CRAN-only. Pass
`repos = BiocManager::repositories()` for the `install_local()` calls.

**codex prints harmless warnings about its own housekeeping on a read-only
filesystem.** Every time `codex` runs - during the build's version-check gate, and
(expected) again during normal use of the final image - it tries some bookkeeping
step (creating PATH aliases, garbage-collecting stale temp dirs from previous
invocations) that fails against a read-only filesystem and prints a warning before
continuing normally. Observed so far:
- `WARNING: proceeding, even though we could not create PATH aliases: Read-only file
  system (os error 30)`
- `WARNING: failed to clean up stale arg0 temp dirs: Directory not empty (os error 39)`
  (`ENOTEMPTY` - it can't delete the stale directory's contents on a read-only
  filesystem, so the directory it's left with isn't empty either)

Both non-fatal (the CLI still runs immediately afterward; the build still succeeds).
A built `.sif` is a read-only squashfs at runtime, so expect to keep seeing these (or
similar) on every `codex` invocation there - not specific to the build, and not
something to chase down further unless codex actually stops working.

**A host personal R library can shadow the container's packages at run time.**
Apptainer binds the invoking user's real `$HOME` into the container by default (this
image relies on that for persisted agent-CLI OAuth credentials - see "Interactive
use" above), and R's default per-user library path
(`~/R/<arch>-library/<Rversion>`) lives under `$HOME` too, ahead of the container's
own site-library in `.libPaths()`. If that directory already exists on the real
host - from unrelated prior R/RStudio work - its packages get picked up *inside* the
container instead of (or in addition to) the ones this image installs. Symptoms:
`apptainer test`/`exec`/`run` reports packages this image deliberately excludes
(e.g. `SeuratObject`) as "installed but not loadable," and packages this image *does*
install can fail with a `dyn.load()` error pointing at a path under `/home/<user>/R/...`
rather than anywhere in the container - e.g.
`unable to load shared object '.../R/x86_64-pc-linux-gnu-library/4.4/DESeq2/libs/DESeq2.so':
libRlapack.so: cannot open shared object file`. That `.so` was compiled against a
different R/BLAS/LAPACK build on the host, not against this image. This cannot
surface during `apptainer build` (the build-time `$HOME` isn't the real user's home),
so a clean build gate followed by a run-time failure on the same package is the
signature of this issue, not a sign the build was wrong.

Fixed by pointing `R_LIBS_USER` at a path specific to this image rather than the
generic host default - see `%environment` in `agentic_downstream.def` (the setting
that actually matters, since Apptainer is the deliverable) and the `ENV R_LIBS_USER`
note in the Dockerfile. Follows the
[Rocker Project's own Singularity guidance](https://rocker-project.org/use/singularity.html):
redirect, don't just disable, so a genuinely-needed personal install still has
somewhere sane to land. To work around this on an already-built image without a
rebuild, pass `--env R_LIBS_USER=/some/empty/path` to `apptainer test`/`exec`/`run`.

`%post` is one shell block with no layer caching (see "Iterating on a failed build"
above), so in a single-file `.def` any change here re-ran the entire apt/Node/R install
chain. With the two-layer build, changing `R_LIBS_USER` only needs the final image
rebuilt, since its `%environment` is the one that takes effect - but keep the base's
copy in step (see "Two-layer build"). In `Dockerfile.base` the `ENV R_LIBS_USER` line
sits at the very end, after everything expensive, so an incremental Docker build of
the base only invalidates that one cheap layer.

This is a general Apptainer + `$HOME`-binding risk, not specific to this image's
package list - `../singlecell_downstream` binds `/home/$USER` the same way (see its
`%help`) and could hit the same shadowing if a conflicting package name exists in a
user's personal library.

**Each agent CLI needs an explicit permission-bypass flag for batch use, even in
"headless" mode.** All three default to an interactive-approval posture that survives
into their non-interactive modes: `claude --print` starts in Manual (read-only) mode,
so it reads `PROMPT_FILE` fine but refuses to write `RESPONSE_FILE`; `codex exec`
pauses for approval unless told not to (and its sandbox cannot run inside Apptainer
at all - see "Security"); `agy -p` is the most dangerous of the three, because it
**soft-denies** any tool needing approval and still exits 0, so an unflagged run
reports success having written nothing. Symptom: the agent reports
something like "the permission to write wasn't granted" and correctly refuses rather
than silently failing. `entrypoint.sh` now passes `claude
--dangerously-skip-permissions`, `codex exec --dangerously-bypass-approvals-and-sandbox`,
and `agy --dangerously-skip-permissions`. This is safe specifically *because* this image's whole purpose is
running a single agent unattended inside an isolated container - Claude Code's own
docs list `claude -p "<prompt>" --dangerously-skip-permissions` under "Run fully
unattended inside a container" for exactly this reason. agy can instead allow specific tools via `"permissions": {"allow": [...]}` in
`~/.gemini/antigravity-cli/settings.json`, a narrower alternative if a task needs only
a known set of commands.

**A host path in the environment silently breaks claude once hostfs is off.** Apptainer
passes host environment variables in by default. On a SLURM node `TMPDIR` is
`/datastore/scratch/users/<user>`, which does not exist inside a `--no-mount hostfs`
container, and `claude --print` then exits 0 with **no output, no response file and no
session record** - it looks as if the job ended instantly for no reason. Fixed by
`--cleanenv` (which `agentic_run.sh` always passes; it forwards only the variables a run
needs), or `--env TMPDIR=/tmp` on a raw command. Any variable pointing at an unmounted
host path is a candidate for the same failure.

**An open stdin makes `codex exec` wait forever.** When stdin is not a terminal and never
closed - a batch job, or a call made from inside an orchestrating agent - `codex exec` prints
`Reading additional input from stdin...` and waits for EOF before it starts. `claude --print` also
reads a non-terminal stdin. `entrypoint.sh` therefore redirects stdin from `/dev/null` before
launching any agent (no agent takes input on stdin; the prompt is always an argument). Direct CLI
calls need `< /dev/null` added by hand.

**CLI argument order is not free.** Two launches failed on flag placement alone:
- `claude --add-dir` is variadic (`--add-dir <directories...>`) and consumes every
  following non-flag argument. Placed last, it swallowed the prompt, and `--print`
  failed with `Input must be provided either through stdin or as a prompt argument`.
  `entrypoint.sh` puts `--add-dir` entries first so `--print` terminates the list.
- codex's `--ask-for-approval` is a top-level option, not an `exec` option (codex-cli
  0.158): after `exec` it errors `unexpected argument '--ask-for-approval'`. Moot now
  that `--dangerously-bypass-approvals-and-sandbox` (an `exec` option) replaces it,
  but relevant if the sandbox ever becomes usable and the flags are split again.
- `agy -p` is passed LAST, directly before the prompt, so the prompt parses correctly
  whether agy treats `-p` as a boolean or as taking the prompt as its value.

Check `<cli> --help` inside the image before assuming a flag is misspelled.

**Two pins predate R 4.4** and should be re-checked if the base image moves again:
ComplexHeatmap at commit `ae0ec42` (2.15.4-era, untagged), and SCPA's archived
`crossmatch` 1.3.1 / `multicross` 2.1.0.

## Known gaps / future work

- **Watch/poll mode**: not implemented. The current design assumes a manager `claude`
  session explicitly spins up one-shot `codex`/`agy` jobs per review round. A
  long-running directory-watching mode can be added later as a change to
  `entrypoint.sh` - a final-image rebuild only (see "Two-layer build"), testable
  beforehand via `ENTRYPOINT_OVERRIDE`.
- **agy self-updates by default.** The image sets `AGY_CLI_DISABLE_AUTO_UPDATE=true`
  (the binary is read-only there anyway); pick up a new agy by rebuilding the final
  layer. The installer always fetches the *latest* release, so agy is unpinned like
  the npm CLIs - `agy --version` in the build log records what was baked in.
- Exact CLI flags/package names for all three agents were verified against public
  docs at the time this image was built, but these tools move fast - if a build or
  run fails on an unrecognized flag, check `claude --help` / `codex exec --help` /
  `agy --help` inside the built image before assuming the `.def`/Dockerfile/
  entrypoint is wrong in some other way.
