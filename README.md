# singlecell_images

Container definitions for the lab's single-cell analysis images.

| Directory | Image | For |
|---|---|---|
| `decontx/` | seurat + decontx (celda) | Ambient RNA decontamination |
| `scCDC/` | seurat + scCDC | Contamination detection/correction |
| `singlecell_downstream/` | seurat + DE / pathway / composition stack | Everything after cell typing — DESeq2, fgsea, SCPA, UCell, speckle, harmony, ComplexHeatmap |
| `agentic_downstream/` | Seurat-free (SingleCellExperiment) downstream stack + claude/codex/gemini CLIs | Same downstream analysis stack without Seurat, plus agentic CLI tooling for cluster-based plan-review workflows |

Each directory has a `Dockerfile`. `singlecell_downstream/` and `agentic_downstream/`
additionally have an Apptainer `.def` file and their own README covering build details
and gotchas.

## Release process

Docker Hub is canonical. Cluster `.sif` images are derived from it, never pushed directly —
a `.sif` is a squashfs file, not an OCI image, so `docker push` does not apply.

**1. Commit and tag.** Tag format is `<image-dir>/<version>`:

```bash
git tag agentic_downstream/0.0.1
git push origin agentic_downstream/0.0.1
```

**2. CI builds and pushes.** `.github/workflows/build-and-push.yml` fires on that tag, builds
the named directory on a native amd64 runner, smoke-tests the image, and pushes
`benjaminvincentlab/<image>:<version>` to Docker Hub.

To build without tagging — recommended the first time, or when testing a change — run the
workflow by hand from the Actions tab and untick **push**. That builds and tests without
publishing.

Requires two repo secrets: `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` (a Docker Hub personal
access token with write access to the `benjaminvincentlab` namespace). Set these via
`gh secret set DOCKERHUB_USERNAME` / `gh secret set DOCKERHUB_TOKEN` (prompts for the value,
keeps it out of shell history and chat transcripts) or the repo's Settings → Secrets and
variables → Actions page — never commit them to a file.

**3. Pull the cluster image** from the published tag, so what runs on the cluster is provably
what was published:

```bash
apptainer pull docker://benjaminvincentlab/<image>:<version>
```

### Why CI rather than a local build

The images are `linux/amd64` for an x86_64 cluster. Building on an arm64 Mac means QEMU
emulation, which produces non-deterministic compiler crashes — a segfaulting `g++`, an internal
compiler error, a broken pipe in an apt post-install script — landing on a different package each
attempt. Building on a native amd64 runner removes that class of failure entirely and needs no
local Docker.

Apptainer can build a `.sif` directly on a native x86_64 host, which is useful for iterating on a
definition (see `singlecell_downstream/README.md` and `agentic_downstream/README.md`). But an
image published that way skips Docker Hub, so the rest of the lab's tooling cannot pull it. Use
direct builds for development; use CI for anything anyone else will consume.

### Versioning

Version numbers follow the lab convention and are not derived from the packages inside. Bump the
version for any change to a definition file, and never re-push an existing tag — analyses record
which image they ran under, and a mutated tag silently invalidates that record.
