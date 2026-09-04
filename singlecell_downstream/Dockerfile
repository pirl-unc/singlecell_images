# singlecell_downstream - see README.md for what this image is for, how to build it,
# and the gotchas behind the less obvious steps below.
#
# Keep in sync with singlecell_downstream.def (identical package content).

FROM --platform=linux/amd64 satijalab/seurat:5.4.0

LABEL org.opencontainers.image.title="singlecell_downstream"
LABEL org.opencontainers.image.description="Downstream single-cell analysis: Seurat / SingleCellExperiment objects, UCell signature scoring, DESeq2 pseudobulk DE, fgsea, SCPA pathway analysis, speckle/limma composition testing, harmony integration, ComplexHeatmap, and survival modelling."
LABEL org.opencontainers.image.source="https://github.com/pirl-unc/singlecell_images"
LABEL org.opencontainers.image.base.name="satijalab/seurat:5.4.0"
LABEL org.opencontainers.image.vendor="Benjamin Vincent Lab, UNC Lineberger"

# libmagick++-6.q16-9t64 is the ImageMagick runtime, required because SpatialExperiment
# imports magick - not because anything here uses ImageMagick. Runtime package, not -dev.
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
        pkg-config && \
    rm -rf /var/lib/apt/lists/*

# Posit Package Manager: prebuilt binaries + a dated snapshot contemporaneous with R 4.4.
# The __linux__/noble/ path must match the base image's distro - a mismatch silently
# falls back to source builds.
RUN echo 'options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/2025-04-01"), \
          BioC_mirror = "https://packagemanager.posit.co/bioconductor", \
          BIOCONDUCTOR_CONFIG_FILE = "https://packagemanager.posit.co/bioconductor/config.yaml", \
          HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(), \
            paste(getRversion(), R.version$platform, R.version$arch, R.version$os)))' \
          >> /usr/local/lib/R/etc/Rprofile.site

RUN Rscript -e "if (!requireNamespace('BiocManager', quietly=TRUE)) install.packages('BiocManager'); if (!requireNamespace('remotes', quietly=TRUE)) install.packages('remotes'); BiocManager::version()"

# CRAN. Only what the base image lacks - Seurat already supplies ggplot2, ggrepel,
# patchwork, purrr, rlang, scales, tibble, irlba, jsonlite, RColorBrewer, matrixStats,
# uwot and FNN; survival and mgcv ship with R.
RUN Rscript -e "install.packages(c( \
      'magrittr', 'data.table', 'dplyr', 'tidyr', 'tidytable', 'forcats', 'stringr', \
      'viridis', 'colorspace', 'digest', 'qs2', 'segmented', \
      'ggforce', 'ggnewscale', 'ggsignif', 'shadowtext', \
      'harmony'))"

# HDF5 cluster rebuilt from source first - the base image's Rhdf5lib links a system
# szip that is not installed. Must precede anything reaching it via DelayedArray.
RUN Rscript -e "BiocManager::install('Rhdf5lib',  update = FALSE, ask = FALSE, force = TRUE)"
RUN Rscript -e "BiocManager::install('rhdf5',     update = FALSE, ask = FALSE, force = TRUE)"
RUN Rscript -e "BiocManager::install('HDF5Array', update = FALSE, ask = FALSE, force = TRUE)"
RUN Rscript -e "library(Rhdf5lib); library(rhdf5); library(HDF5Array); message('HDF5 stack OK')"

# Bioconductor. One package per layer so a failure is cached and named.
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
# clustermole needs Bioconductor packages that install.packages() will not fetch.
RUN Rscript -e "remotes::install_version('crossmatch', version='1.3.1', upgrade='never')"
RUN Rscript -e "remotes::install_version('multicross', version='2.1.0', upgrade='never')"
RUN Rscript -e "BiocManager::install('GSEABase',   update = FALSE, ask = FALSE)"
RUN Rscript -e "BiocManager::install('GSVA',       update = FALSE, ask = FALSE)"
RUN Rscript -e "BiocManager::install('singscore',  update = FALSE, ask = FALSE)"
RUN Rscript -e "install.packages('clustermole')"

# GitHub packages via codeload + curl, pinned to commit SHAs. install_github() is
# avoided: it resolves refs through the rate-limited GitHub API.
# ComplexHeatmap must precede SCPA, which depends on it.
RUN curl -fsSL -o /tmp/ComplexHeatmap.tar.gz \
      https://codeload.github.com/jokergoo/ComplexHeatmap/tar.gz/ae0ec42cd2e4e0446c114d23dcf43cf2c2f585c8 && \
    Rscript -e "options(repos = BiocManager::repositories()); remotes::install_local('/tmp/ComplexHeatmap.tar.gz', upgrade='never')" && \
    rm -f /tmp/ComplexHeatmap.tar.gz

RUN curl -fsSL -o /tmp/SCPA.tar.gz \
      https://codeload.github.com/jackbibby1/SCPA/tar.gz/68b6c9954a0eca82b4cfc990a963d5f5ca1f711b && \
    Rscript -e "options(repos = BiocManager::repositories()); remotes::install_local('/tmp/SCPA.tar.gz', upgrade='never')" && \
    rm -f /tmp/SCPA.tar.gz

# Fatal gate - R install failures are warnings, so nothing upstream catches a miss.
RUN Rscript -e "invisible(lapply(c( \
      'Seurat','SingleCellExperiment','DESeq2','fgsea','scran','scater','speckle','limma','UCell', \
      'SCPA','clustermole','GSVA','ComplexHeatmap','harmony','survival','segmented','mgcv','Matrix', \
      'magrittr','data.table','dplyr','tidyr','tidytable','forcats','stringr','viridis','colorspace', \
      'digest','qs2','ggplot2','ggrepel','ggforce','ggnewscale','ggsignif','shadowtext','patchwork'), \
      function(p) { library(p, character.only=TRUE); message(p, ' OK') }))"

# Informational sweep - unused base-image packages with absent system libraries are
# expected here (BPCells, hdf5r, RMariaDB, RPostgres, sf, units, tcltk).
RUN Rscript -e "pkgs <- rownames(installed.packages()); \
      bad <- pkgs[!vapply(pkgs, function(p) isTRUE(tryCatch({loadNamespace(p); TRUE}, error=function(e) FALSE)), logical(1))]; \
      if (length(bad)) message('NOTE - installed but not loadable: ', paste(bad, collapse=', ')) \
      else message('all ', length(pkgs), ' installed packages load cleanly')"

RUN Rscript -e "message('R ', getRversion(), ' | Seurat ', packageVersion('Seurat'), ' | Matrix ', packageVersion('Matrix'), ' | Bioc ', BiocManager::version())"
