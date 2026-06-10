#!/usr/bin/env bash
# Build/pull Apptainer (.sif) images for an HPC run.
#
#   - CellProfiler & pycytominer: pulled from their official registries.
#   - DeepProfiler & cytopipe: built locally as Docker images first, then converted.
#
# STUB: pin tags/digests and a registry before production use.

set -euo pipefail

CACHEDIR="${APPTAINER_CACHEDIR:-/scratch/$USER/apptainer}"
mkdir -p "$CACHEDIR"
cd "$CACHEDIR"

CELLPROFILER_IMAGE="${CELLPROFILER_IMAGE:-cellprofiler/cellprofiler:4.2.8}"
PYCYTOMINER_IMAGE="${PYCYTOMINER_IMAGE:-cytomining/pycytominer:latest}"
DEEPPROFILER_IMAGE="${DEEPPROFILER_IMAGE:-deepprofiler:dev}"
CYTOPIPE_IMAGE="${CYTOPIPE_IMAGE:-cytopipe:dev}"

# Pull official images directly into .sif.
apptainer pull cellprofiler.sif "docker://${CELLPROFILER_IMAGE}"
apptainer pull pycytominer.sif "docker://${PYCYTOMINER_IMAGE}"

# Convert locally-built images (build them first — see ../../containers/README.md).
# Option A: from a registry you pushed to:
#   apptainer pull deepprofiler.sif "docker://${DEEPPROFILER_IMAGE}"
#   apptainer pull cytopipe.sif     "docker://${CYTOPIPE_IMAGE}"
# Option B: from the local docker daemon:
apptainer build deepprofiler.sif "docker-daemon://${DEEPPROFILER_IMAGE}"
apptainer build cytopipe.sif     "docker-daemon://${CYTOPIPE_IMAGE}"

echo "Built .sif images in $CACHEDIR"
