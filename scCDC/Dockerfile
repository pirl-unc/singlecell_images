FROM satijalab/seurat:5.0.0
# OS: GNU/Linux Ubuntu 20.04 LTS (focal fossa)

RUN Rscript -e "BiocManager::install('UCell')"
# Optional: Confirm it's installed
RUN Rscript -e "library(UCell); print('UCell loaded successfully')"

# add scCDC which needs to be installed from source after installing dependencies
RUN Rscript -e "install.packages(c('xfun', 'knitr', 'ddpcr', 'pROC'))"
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/ZJU-UoE-CCW-LAB/scCDC.git /tmp/scCDC && \
    R CMD INSTALL --no-docs --no-help --no-html /tmp/scCDC && \
    rm -rf /tmp/scCDC

RUN Rscript -e "library(scCDC); print('scCDC loaded successfully')"

