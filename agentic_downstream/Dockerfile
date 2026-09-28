# agentic_downstream - see README.md for what this image is for, how to build it, and
# the gotchas behind the less obvious steps below.
#
# Keep in sync with agentic_downstream.def (identical package content). The .def file
# is the actual deliverable - see README.md "Why a .def file" for why.

FROM --platform=linux/amd64 bioconductor/bioconductor_docker:RELEASE_3_20

LABEL org.opencontainers.image.title="agentic_downstream"
LABEL org.opencontainers.image.description="Seurat-free downstream single-cell analysis (SingleCellExperiment, UCell, DESeq2 pseudobulk DE, fgsea, SCPA, speckle/limma, harmony, ComplexHeatmap, survival modelling) plus claude/codex/gemini CLI agents for cluster-based agentic review workflows."
LABEL org.opencontainers.image.source="https://github.com/pirl-unc/singlecell_decontamination"
LABEL org.opencontainers.image.base.name="bioconductor/bioconductor_docker:RELEASE_3_20"
LABEL org.opencontainers.image.vendor="Benjamin Vincent Lab, UNC Lineberger"

# libmagick++-6.q16-9t64 is the ImageMagick runtime, required because SpatialExperiment
# imports magick - not because anything here uses ImageMagick. Runtime package, not
# -dev (mirrors the fix in ../singlecell_downstream, which hit this same chain via
# GSVA/clustermole/SCPA - identical here since we install the same three).
RUN apt-get update && \
    apt-get install -y \
        libmagick++-6.q16-9t64 \
        libxml2-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        libgsl-dev \
        libfontconfig1-dev \
        libfreetype6-dev \
        libpng-dev \
        libtiff5-dev \
        libjpeg-dev \
        libcairo2-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        cmake \
        curl \
        pkg-config \
        git \
        ca-certificates \
        gnupg && \
    rm -rf /var/lib/apt/lists/*

# Node.js 20.x LTS via NodeSource. Ubuntu noble's apt `nodejs` (18.x) is old enough to
# risk compatibility issues with the agent CLIs below, which move fast and target
# current Node. Not needed by ../singlecell_downstream - new to this image.
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Agent CLIs. No non-root USER is set: the installed binaries/packages only need
# read+execute at runtime, and this image is designed to run under Singularity/
# Apptainer on the cluster, which maps the container process to the invoking host
# user and binds that user's real $HOME - so per-user config/credential directories
# (~/.claude, ~/.codex, ~/.gemini, ~/.npm) land in the actual host home directory
# whether credentials come from an interactive OAuth login or from API-key env vars
# at batch-job time.
RUN npm install -g \
        @anthropic-ai/claude-code \
        @openai/codex \
        @google/gemini-cli && \
    npm cache clean --force

# bioconductor/bioconductor_docker:RELEASE_3_20 already configures a Posit-backed
# binary CRAN repo pointed at __linux__/noble (verified by inspection - see README.md
# "Gotchas" for why this must never be assumed). Unlike ../singlecell_downstream's
# satijalab/seurat base, nothing needs to be added here for that.
RUN Rscript -e "if (!requireNamespace('BiocManager', quietly=TRUE)) install.packages('BiocManager'); if (!requireNamespace('remotes', quietly=TRUE)) install.packages('remotes'); BiocManager::version()"

# ------------------------------------------------------------------------------
# CRAN. Unlike ../singlecell_downstream/Dockerfile, NONE of these arrive for free
# from a Seurat base image, so this list is broader: ggplot2/ggrepel/patchwork/
# Matrix/irlba/uwot/FNN/matrixStats/RColorBrewer are only implicit dependencies
# there because satijalab/seurat supplies them; here they're explicit.
# ------------------------------------------------------------------------------
RUN Rscript -e "install.packages(c( \
      'ggplot2', 'ggrepel', 'patchwork', 'Matrix', 'irlba', 'uwot', 'FNN', \
      'matrixStats', 'RColorBrewer', \
      'magrittr', 'data.table', 'dplyr', 'tidyr', 'tidytable', 'forcats', 'stringr', \
      'viridis', 'colorspace', 'digest', 'qs2', 'segmented', \
      'ggforce', 'ggnewscale', 'ggsignif', 'shadowtext', \
      'harmony'))"

# HDF5 cluster rebuilt from source first - the base image's Rhdf5lib links a system
# szip that is not installed. GSVA reaches it via the DelayedArray/HDF5Array chain,
# so this must precede the Bioconductor loop below. Same fix as
# ../singlecell_downstream/Dockerfile.
RUN Rscript -e "BiocManager::install('Rhdf5lib',  update = FALSE, ask = FALSE, force = TRUE)"
RUN Rscript -e "BiocManager::install('rhdf5',     update = FALSE, ask = FALSE, force = TRUE)"
RUN Rscript -e "BiocManager::install('HDF5Array', update = FALSE, ask = FALSE, force = TRUE)"
RUN Rscript -e "library(Rhdf5lib); library(rhdf5); library(HDF5Array); message('HDF5 stack OK')"

# ------------------------------------------------------------------------------
# Bioconductor. One package per RUN layer on purpose - a failed layer discards
# everything in it, so per-package layers mean a retry only redoes the one that
# failed.
# ------------------------------------------------------------------------------
RUN Rscript -e "BiocManager::install('SingleCellExperiment', update = FALSE, ask = FALSE)"
RUN Rscript -e "BiocManager::install('edgeR',                update = FALSE, ask = FALSE)"
RUN Rscript -e "BiocManager::install('limma',                update = FALSE, ask = FALSE)"
RUN Rscript -e "BiocManager::install('scuttle',              update = FALSE, ask = FALSE)"
RUN Rscript -e "BiocManager::install('scater',               update = FALSE, ask = FALSE)"
RUN Rscript -e "BiocManager::install('scran',                update = FALSE, ask = FALSE)"
RUN Rscript -e "BiocManager::install('DESeq2',               update = FALSE, ask = FALSE)"
RUN Rscript -e "BiocManager::install('fgsea',                update = FALSE, ask = FALSE)"
RUN Rscript -e "BiocManager::install('speckle',              update = FALSE, ask = FALSE)"
RUN Rscript -e "BiocManager::install('UCell',                update = FALSE, ask = FALSE)"

# SCPA's dependency chain, in order. crossmatch and multicross are CRAN-archived;
# clustermole needs Bioconductor packages that install.packages() will not fetch
# (getOption("repos") is CRAN-only for install.packages()/install_local()).
RUN Rscript -e "remotes::install_version('crossmatch', version='1.3.1', upgrade='never')"
RUN Rscript -e "remotes::install_version('multicross', version='2.1.0', upgrade='never')"
RUN Rscript -e "BiocManager::install('GSEABase',   update = FALSE, ask = FALSE)"
RUN Rscript -e "BiocManager::install('GSVA',       update = FALSE, ask = FALSE)"
RUN Rscript -e "BiocManager::install('singscore',  update = FALSE, ask = FALSE)"
RUN Rscript -e "install.packages('clustermole')"

# GitHub packages via codeload + curl, pinned to commit SHAs. install_github() is
# avoided: it resolves refs through the rate-limited GitHub API (60/hr/IP,
# trivially exhausted behind a shared campus address). ComplexHeatmap must precede
# SCPA, which depends on it.
RUN curl -fsSL -o /tmp/ComplexHeatmap.tar.gz \
      https://codeload.github.com/jokergoo/ComplexHeatmap/tar.gz/ae0ec42cd2e4e0446c114d23dcf43cf2c2f585c8 && \
    Rscript -e "options(repos = BiocManager::repositories()); remotes::install_local('/tmp/ComplexHeatmap.tar.gz', upgrade='never')" && \
    rm -f /tmp/ComplexHeatmap.tar.gz

RUN curl -fsSL -o /tmp/SCPA.tar.gz \
      https://codeload.github.com/jackbibby1/SCPA/tar.gz/68b6c9954a0eca82b4cfc990a963d5f5ca1f711b && \
    Rscript -e "options(repos = BiocManager::repositories()); remotes::install_local('/tmp/SCPA.tar.gz', upgrade='never')" && \
    rm -f /tmp/SCPA.tar.gz

# Fatal gate - R install failures are warnings (install.packages()/install_local()
# return normally on failure), so nothing upstream catches a miss without this.
RUN Rscript -e "invisible(lapply(c( \
      'SingleCellExperiment','DESeq2','fgsea','scran','scater','speckle','limma','UCell', \
      'SCPA','clustermole','GSVA','ComplexHeatmap','harmony','survival','segmented','mgcv','Matrix', \
      'magrittr','data.table','dplyr','tidyr','tidytable','forcats','stringr','viridis','colorspace', \
      'digest','qs2','ggplot2','ggrepel','ggforce','ggnewscale','ggsignif','shadowtext','patchwork', \
      'irlba','uwot','FNN','matrixStats','RColorBrewer'), \
      function(p) { library(p, character.only=TRUE); message(p, ' OK') }))"

# Informational sweep - unused base-image packages with absent system libraries may
# be expected here; not fatal.
RUN Rscript -e "pkgs <- rownames(installed.packages()); \
      bad <- pkgs[!vapply(pkgs, function(p) isTRUE(tryCatch({loadNamespace(p); TRUE}, error=function(e) FALSE)), logical(1))]; \
      if (length(bad)) message('NOTE - installed but not loadable: ', paste(bad, collapse=', ')) \
      else message('all ', length(pkgs), ' installed packages load cleanly')"

RUN Rscript -e "message('R ', getRversion(), ' | Bioc ', BiocManager::version())" && \
    node --version && npm --version && \
    claude --version && codex --version && gemini --version

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
