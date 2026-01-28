FROM satijalab/seurat:5.0.0
# OS: GNU/Linux Ubuntu 20.04 LTS (focal fossa)

RUN Rscript -e "BiocManager::install('UCell')"
# Optional: Confirm it's installed
RUN Rscript -e "library(UCell); print('UCell loaded successfully')"

# Install celda dependencies
RUN apt-get update && \
    apt-get install -y \
        libxml2-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        libgsl-dev && \
    rm -rf /var/lib/apt/lists/*

RUN Rscript -e "BiocManager::install(c('abind', 'ape', 'askpass', 'BH', 'BiocManager', 'bit', 'bit64', 'bitops','blob', 'bslib', 'cachem', 'caTools', 'cli', 'colorspace', 'commonmark',   'cowplot', 'cpp11', 'crayon', 'crosstalk', 'data.table', 'DBI','deldir', 'DEoptimR', 'digest', 'docopt', 'dotCall64', 'dplyr', 'dqrng','enrichR', 'evaluate', 'fansi', 'farver', 'fastDummies', 'fastICA', 'fastmap', 'fitdistrplus', 'FNN', 'fontawesome', 'fs', 'futile.logger', 'future', 'future.apply', 'generics', 'ggplot2', 'ggrepel', 'ggridges',    'globals', 'glue', 'gplots', 'gtable', 'gtools', 'hdf5r', 'here', 'highr', 'hms', 'htmltools', 'htmlwidgets', 'httpuv', 'igraph', 'isoband','jsonlite', 'kernlab', 'knitr', 'later', 'leiden', 'leidenbase', 'lifecycle', 'listenv', 'locfit', 'magrittr', 'mathjaxr',     'MatrixModels', 'matrixStats', 'metap', 'mime', 'miniUI', 'mixtools', 'mnormt', 'multcomp', 'munsell', 'mutoss', 'mvtnorm', 'openssl', 'parallelly', 'patchwork', 'pbapply', 'pheatmap', 'pillar', 'plotly','plotrix', 'polyclip', 'progress', 'progressr', 'promises', 'proxy',     'purrr', 'qlcMatrix', 'quantreg', 'R.oo', 'R.utils', 'R6', 'RANN', 'rappdirs', 'rbibutils', 'Rcpp', 'RcppAnnoy', 'RcppArmadillo', 'RcppEigen', 'RcppHNSW', 'RcppParallel', 'RcppTOML', 'RcppZiggurat', 'RCurl', 'Rdpack', 'remotes', 'reshape2', 'restfulr', 'reticulate', 'Rfast', 'Rfast2','rjson', 'rlang', 'rmarkdown', 'robustbase', 'ROCR', 'rprojroot','RSpectra', 'RSQLite', 'Rtsne', 'RUnit', 'sandwich', 'sass', 'scales','sctransform', 'segmented', 'shiny', 'slam','sn', 'sp', 'spam', 'SparseM', 'sparsesvd', 'spatstat.data',    'spatstat.explore', 'spatstat.geom', 'spatstat.random', 'spatstat.sparse', 'spatstat.utils', 'stringi', 'stringr', 'sys', 'tensor', 'TH.data', 'tibble', 'tidyr', 'tidyselect', 'tinytex', 'utf8', 'uwot', 'vctrs', 'VGAM', 'viridis', 'withr', 'WriteXLS', 'xfun', 'XML', 'yaml', 'zoo' ), update = TRUE, ask = FALSE, force = TRUE)"

RUN Rscript -e "install.packages('https://cran.r-project.org/src/contrib/Archive/Matrix/Matrix_1.6-5.tar.gz', repos=NULL, type='source')"

# Install system dependencies
RUN apt-get update && \
    apt-get install -y \
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
        libmagick++-dev \
	libwebp-dev \
	curl \
	pkg-config && \
    rm -rf /var/lib/apt/lists/*

# Now install celda
RUN Rscript -e "BiocManager::install('celda', force=TRUE, ask=FALSE)"
