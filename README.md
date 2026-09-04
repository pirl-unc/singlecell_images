# singlecell_images
<<<<<<< Updated upstream
Docker/def files for images for singlecell work.

decontx - seurat + decontx ( celda )
* for decontamination using the decontx method
  
scCDC - seurat + scCDC
* for decontamination using the scCDC method
  
singlecell_downstream - seurat, singlecellexperiment, deseq, fgsea, scpa, ucell, ...
* for common downstream analysis steps
=======

Container definitions for the lab's single-cell analysis images.

| Directory | Image | For |
|---|---|---|
| `decontx/` | seurat + decontx (celda) | Ambient RNA decontamination |
| `scCDC/` | seurat + scCDC | Contamination detection/correction |
| `singlecell_downstream/` | seurat + DE / pathway / composition stack | Everything after cell typing — DESeq2, fgsea, SCPA, UCell, speckle, harmony, ComplexHeatmap |

Each directory has a `Dockerfile`. `singlecell_downstream/` additionally has an Apptainer
`.def` file and its own README covering build details and gotchas.

## Release process

Docker Hub is canonical. Cluster `.sif` images are derived from it, never pushed directly —
a `.sif` is a squashfs file, not an OCI image, so `docker push` does not apply.

**1. Commit and tag.** Tag format is `<image-dir>/<version>`:

```bash
git tag singlecell_downstream/0.0.1.2
git push origin singlecell_downstream/0.0.1.2
```

**2. CI builds and pushes.** `.github/workflows/build-and-push.yml` fires on that tag, builds
the named directory on a native amd64 runner, smoke-tests the image, and pushes
`benjaminvincentlab/<image>:<version>` to Docker Hub.

To build without tagging — recommended the first time, or when testing a change — run the
workflow by hand from the Actions tab and untick **push**. That builds and tests without
publishing.

Requires two repo secrets: `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` (a Docker Hub personal
access token with write access to the `benjaminvincentlab` namespace).

**3. Pull the cluster image** from the published tag, so what runs on the cluster is provably
what was published:

```bash
singularity pull docker://benjaminvincentlab/<image>:<version>
```

### Why CI rather than a local build

The images are `linux/amd64` for an x86_64 cluster. Building on an arm64 Mac means QEMU
emulation, which produces non-deterministic compiler crashes — a segfaulting `g++`, an internal
compiler error, a broken pipe in an apt post-install script — landing on a different package each
attempt. Building on a native amd64 runner removes that class of failure entirely and needs no
local Docker.

Apptainer can build a `.sif` directly on a native x86_64 host, which is useful for iterating on a
definition (see `singlecell_downstream/README.md`). But an image published that way skips Docker
Hub, so the rest of the lab's tooling cannot pull it. Use direct builds for development; use CI
for anything anyone else will consume.

### Versioning

Version numbers follow the lab convention and are not derived from the packages inside. Bump the
version for any change to a definition file, and never re-push an existing tag — analyses record
which image they ran under, and a mutated tag silently invalidates that record.
>>>>>>> Stashed changes
