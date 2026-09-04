# singlecell_downstream

Downstream single-cell analysis environment — everything after alignment and cell typing.

**Base:** `satijalab/seurat:5.4.0` — Seurat 5.4.0 / SeuratObject 5.3.0, R 4.4.2, Ubuntu 24.04 noble,
gcc 13.3. R 4.4 was chosen to match the RStudio installs the analyses actually run on.

## What it's for

| Capability | Packages |
|---|---|
| Pseudobulk differential expression | DESeq2, edgeR, limma |
| GSEA / pathway enrichment | fgsea |
| Pathway divergence | SCPA (+ crossmatch, multicross, clustermole, GSVA, GSEABase, singscore) |
| Signature scoring | UCell |
| Cell type composition testing | speckle, limma |
| Normalization, PCA, QC | SingleCellExperiment, scran, scater, scuttle, irlba |
| Batch integration / embedding | harmony, uwot |
| Survival and non-linear association | survival, mgcv, segmented |
| Figures | ggplot2 stack, ggsignif, ggforce, ggnewscale, patchwork, ComplexHeatmap, viridis |

Not for decontamination — see `../decontx` and `../scCDC`.

## Files

- `singlecell_downstream.def` — Apptainer definition; **this is what gets built**
- `Dockerfile` — equivalent Docker recipe, kept as a portable record

The two are identical in package content. **Change both together.**

## Why a .def file

The deliverable is a `.sif` for a Singularity/Apptainer HPC cluster. Building the Docker image on an
arm64 Mac meant emulating linux/amd64 under QEMU, which produced repeated non-deterministic
failures — `g++` segfaulting mid-compile, an internal compiler error, a `BrokenPipeError` in an apt
post-install script. None were code problems; the emulator was crashing, on a different package each
attempt.

Building with Apptainer on a native x86_64 host removes that entire class and emits the `.sif`
directly — no Docker daemon, no registry round trip, no paid remote builder. The Dockerfile remains
for anyone who wants a Docker image on amd64 hardware.

## Build

On a native **x86_64** host with Apptainer (verified: apptainer 1.3.2, Rocky 9.4):

```bash
export APPTAINER_TMPDIR=/datastore/scratch/users/$USER
apptainer build --fakeroot \
  /datastore/scratch/users/$USER/singlecell_downstream_<version>.sif \
  singlecell_downstream.def
```

`--fakeroot` works without an `/etc/subuid` entry — Apptainer falls back to a root-mapped user
namespace, which is sufficient for `apt-get install` on a glibc base. Build into scratch; the image
is ~1.5 GB. Then move to the final directory.

Docker equivalent, if building on amd64 hardware:

```bash
docker build --platform linux/amd64 -t benjaminvincentlab/singlecell_downstream:<version> .
```

### Iterating on a failed build

`%post` is a single shell block with no layer caching, so a failure restarts it. To test a fix
against an existing image without rebuilding:

```bash
mkdir -p /tmp/testlib
apptainer exec --bind /tmp/testlib:/testlib <image>.sif Rscript -e \
  ".libPaths(c('/testlib', .libPaths())); BiocManager::install('<pkg>', lib='/testlib', force=TRUE); library(<pkg>, lib.loc='/testlib')"
```

This validates a fix in minutes instead of at the end of a 25-minute build. `--writable-tmpfs` alone
does **not** work — it doesn't make `/usr/local/lib/R/site-library` writable.

## Verify

The build runs two gates automatically, and `%test` is re-runnable:

```bash
apptainer test <image>.sif
```

A pass prints `all N required packages present and loadable`, then a per-package `OK` list, then
the version line. It also prints a note listing packages that are installed but not loadable —
`BPCells, hdf5r, RMariaDB, RPostgres, sf, units, tcltk` are expected there. They ship with the base
image, need absent system libraries, and nothing here imports them.

## Gotchas

Recorded because each one cost a build cycle.

**Posit binary repos are distro-specific and fail silently.** The `__linux__/<codename>/` path in
`Rprofile.site` must match the base image's actual distro. A wrong codename doesn't error — P3M just
serves source packages instead of binaries, and a build that should take minutes compiles for hours.
Verify by inspection, not assumption:

```bash
apptainer exec docker://satijalab/seurat:5.4.0 bash -c 'cat /etc/os-release | head -3; R --version | head -1'
```

**R package install failures are warnings, not errors.** `install.packages()` and
`install_local()` return normally after a failed install, so `Rscript` exits 0 and `set -e` never
fires. A build once ran 20 minutes past a dead SCPA install and shipped an image without it. Hence
the explicit `requireNamespace()` gate at the end of `%post`.

**A failing `%test` does not fail an Apptainer build.** It writes the `.sif` and exits 0 regardless.
Anything that must gate the build belongs in `%post`.

**The base image ships R packages whose system libraries are absent.** Two bite:

- `SpatialExperiment` imports `magick`, so `libmagick++-6.q16-9t64` is required even though nothing
  here uses ImageMagick directly. Without it: SpatialExperiment → GSVA → clustermole → SCPA all
  fail. Install the runtime package, not `-dev`, which drags in ghostscript and a Python toolchain.
- `Rhdf5lib` is compiled against a system szip that isn't installed (`libsz.so.2: cannot open shared
  object file`). GSVA reaches it via the DelayedArray/HDF5Array chain. Fix by force-reinstalling
  `Rhdf5lib`, `rhdf5` and `HDF5Array` from source so they link their own bundled HDF5 — simpler than
  hunting the right apt package.

**GitHub installs.** `remotes::install_github()` resolves refs through `api.github.com`, rate limited
to 60 unauthenticated calls/hour per IP, and R's `download.file()` couldn't reach GitHub from inside
the build at all. Fetch with `curl` from `codeload.github.com` and `install_local()` instead. Pin
commit SHAs while you're there — `install_github('user/repo')` tracks a moving HEAD.

**Install order matters for SCPA.** It needs `clustermole` and `ComplexHeatmap` present first, and
`clustermole` needs Bioconductor packages that `install.packages()` won't fetch because
`getOption("repos")` is CRAN-only. Pass `repos = BiocManager::repositories()` for the
`install_local()` calls.

**Two pins predate R 4.4** and should be re-checked if the base image moves again: ComplexHeatmap at
commit `ae0ec42` (2.15.4-era, untagged), and SCPA's archived `crossmatch` 1.3.1 / `multicross` 2.1.0.

**Don't reinstall the base image's package tree.** An earlier version carried a ~130-package
`BiocManager::install()` list inherited from a different base. Seurat's dependencies already ship
with the image, and reinstalling them caused version skew (`deldir`/`spatstat.geom`/`RcppParallel`)
and hours of needless compilation.
