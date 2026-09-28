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

It also bundles the `claude`, `codex`, and `gemini` CLI agents (plus Node.js) so it can
run as an agentic review environment on the cluster via Apptainer + Slurm: an
interactive `claude` session can act as a "manager" iterating on an R analysis plan,
and spin up one-shot `codex`/`gemini` batch jobs pointed at a shared bound directory to
get a technical review, repeating until satisfied.

## What's different from `singlecell_downstream`

| | singlecell_downstream | agentic_downstream |
|---|---|---|
| Base image | `satijalab/seurat:5.4.0` | `bioconductor/bioconductor_docker:RELEASE_3_20` |
| Seurat / SeuratObject | included | **not included** |
| Object model | Seurat + SCE | SCE only |
| Agent CLIs | none | claude, codex, gemini + Node |
| Binary CRAN repo | configured manually (base doesn't ship one) | ships preconfigured on `__linux__/noble` |

If you're porting an analysis script from `singlecell_downstream` to this image, check
it for direct `Seurat::` calls first - those need an SCE-based equivalent, since Seurat
itself isn't here to fall back on.

## Files

- `agentic_downstream.def` - Apptainer definition; **this is what gets built**
- `Dockerfile` - equivalent Docker recipe, kept as a portable record
- `entrypoint.sh` - the batch-job launcher; copied into the image by both of the above
  (`%files` in the `.def`, `COPY` in the Dockerfile) and invoked by the `.def`'s
  `%runscript`

The `.def` and `Dockerfile` are identical in package content. **Change both together.**

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

On a native **x86_64** host with Apptainer:

```bash
export APPTAINER_TMPDIR=/datastore/scratch/users/$USER
apptainer build --fakeroot \
  /datastore/scratch/users/$USER/agentic_downstream_<version>.sif \
  agentic_downstream.def
```

`--fakeroot` works without an `/etc/subuid` entry - Apptainer falls back to a
root-mapped user namespace, sufficient for `apt-get install`/`npm install -g` on a
glibc base. Build into scratch, then move the `.sif` to its final directory.

Docker equivalent, if building on amd64 hardware:

```bash
docker build --platform linux/amd64 -t benjaminvincentlab/agentic_downstream:<version> .
```

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

The build runs two gates automatically (R packages, then agent CLI versions), and
`%test` is re-runnable:

```bash
apptainer test <image>.sif
```

A pass prints `all N required packages present and loadable`, a per-package `OK`
list, the R/Bioc version line, and each CLI's `--version` output.

## Interactive use (login, ad hoc work)

`%runscript` (what `apptainer run` invokes) expects an agent name + directory - see
"Batch use" below. For interactive use, including the one-time OAuth login each CLI
needs before it can run without an API key, bypass it entirely:

```bash
apptainer shell --bind "$HOME" <image>.sif
apptainer exec --bind "$HOME" <image>.sif bash

# Docker equivalent
docker run -it --entrypoint bash benjaminvincentlab/agentic_downstream:<version>
```

`apptainer shell`/`exec` ignore `%runscript` by design. From that shell, run `claude`,
`codex`, or `gemini` directly. Apptainer binds the real host `$HOME` and runs the
container process as the invoking user (not root, not a baked-in image user), so
credentials from an interactive login land in `~/.claude`, `~/.codex`, `~/.gemini` on
your actual home directory and persist across future runs - both interactive and
batch.

## Batch use (the plan-review workflow)

```bash
apptainer run --bind /path/to/shared/dir \
  --env ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  agentic_downstream.sif claude /path/to/shared/dir

# equivalently, via env vars instead of positional args:
AGENT=codex PROMPT_DIR=/path/to/shared/dir \
  apptainer run --bind /path/to/shared/dir --env OPENAI_API_KEY="$OPENAI_API_KEY" \
  agentic_downstream.sif
```

Example `sbatch` script for spinning up a codex review job:

```bash
#!/bin/bash
#SBATCH --job-name=codex-review
#SBATCH --time=00:30:00
#SBATCH --mem=4G

apptainer run --bind /proj/shared/plan_review \
  --env OPENAI_API_KEY="$OPENAI_API_KEY" \
  agentic_downstream.sif codex /proj/shared/plan_review
```

`gemini`'s equivalent job swaps in `GEMINI_API_KEY` and
`agentic_downstream.sif gemini /proj/shared/plan_review`.

### Env var passthrough caveat

Unlike Docker, Apptainer passes host environment variables through to the container
**by default**. If a job uses `--cleanenv` (common in shared-cluster Slurm setups to
avoid leaking unrelated environment into jobs), that passthrough is disabled and env
vars must instead be prefixed `APPTAINERENV_` (or `SINGULARITYENV_` on older
Singularity installs), e.g.:

```bash
APPTAINERENV_OPENAI_API_KEY="$OPENAI_API_KEY" \
  apptainer run --cleanenv --bind /proj/shared/plan_review \
  agentic_downstream.sif codex /proj/shared/plan_review
```

Check whether your Slurm job template uses `--cleanenv` before assuming a bare
`export` in the submitting shell is enough.

### API keys

| Agent | Env var |
|---|---|
| claude | `ANTHROPIC_API_KEY` |
| codex | `OPENAI_API_KEY` (mirrored to `CODEX_API_KEY` automatically by `entrypoint.sh` if only `OPENAI_API_KEY` is set) |
| gemini | `GEMINI_API_KEY` |

API keys are only needed for headless/batch runs. Interactive sessions that have
already done a one-time OAuth login (see above) don't need them, since credentials
persist in the bound `$HOME`.

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

### Model and reasoning-effort defaults

| Env var | Default | Effect |
|---|---|---|
| `AGENT_MODEL` | unset (CLI's own default) | Passed as `--model`/`-m` to whichever agent runs. Left unset by default deliberately - pinning a specific model id here would go stale as providers ship new models faster than this file gets updated. |
| `AGENT_EFFORT` | `high` | claude: exported as `CLAUDE_CODE_EFFORT_LEVEL` (`low`/`medium`/`high`/`xhigh`/`max`). codex: passed as `-c model_reasoning_effort="..."` (`low`/`medium`/`high`, plus `xhigh` in some SDK contexts). gemini: **currently a no-op** - gemini-cli does not yet expose a stable CLI flag for thinking budget/reasoning effort (tracked upstream in google-gemini/gemini-cli). Revisit once that lands. |

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

**codex prints a harmless "could not create PATH aliases" warning.** Every time
`codex` runs - during the build's version-check gate, and (expected) again during
normal use of the final image - it tries to write some PATH-alias bookkeeping and,
finding the filesystem read-only at that point, prints
`WARNING: proceeding, even though we could not create PATH aliases: Read-only file
system (os error 30)` and continues normally. Non-fatal (the CLI still runs; the
build still succeeds). A built `.sif` is a read-only squashfs at runtime, so expect
to see this on every `codex` invocation there too - it's not specific to the build.

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

Note that fixing this still requires a full `.sif` rebuild either way, regardless of
where in `agentic_downstream.def` the fix lives: `%post` is one shell block with no
layer caching (see "Iterating on a failed build" above), so `apptainer build`
re-executes the entire apt/Node/R install chain from scratch every time, no matter
what changed or where. The Dockerfile *does* have Docker's layer caching, which is
why its `ENV R_LIBS_USER` line is placed at the very end, after everything expensive -
that ordering is meaningless for the `.def`/Apptainer, but keeps an incremental Docker
build cheap if this file is ever rebuilt that way.

This is a general Apptainer + `$HOME`-binding risk, not specific to this image's
package list - `../singlecell_downstream` binds `/home/$USER` the same way (see its
`%help`) and could hit the same shadowing if a conflicting package name exists in a
user's personal library.

**Two pins predate R 4.4** and should be re-checked if the base image moves again:
ComplexHeatmap at commit `ae0ec42` (2.15.4-era, untagged), and SCPA's archived
`crossmatch` 1.3.1 / `multicross` 2.1.0.

## Known gaps / future work

- **Watch/poll mode**: not implemented. The current design assumes a manager `claude`
  session explicitly spins up one-shot `codex`/`gemini` jobs per review round. A
  long-running directory-watching mode can be added later as a change to
  `entrypoint.sh` - a small, cheap rebuild, not a redo of the R/Bioc layers.
- **gemini reasoning effort**: no-op until gemini-cli ships a stable flag (see table
  above).
- Exact CLI flags/package names for all three agents were verified against public
  docs at the time this image was built, but these tools move fast - if a build or
  run fails on an unrecognized flag, check `claude --help` / `codex exec --help` /
  `gemini --help` inside the built image before assuming the `.def`/Dockerfile/
  entrypoint is wrong in some other way.
