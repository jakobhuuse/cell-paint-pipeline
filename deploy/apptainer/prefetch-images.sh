#!/usr/bin/env bash
# Prefetch the pipeline's container images into the shared Apptainer cache so the first real
# Nextflow run doesn't serialize on image download/conversion.
#
# Run ON THE HEAD NODE once /data is mounted. Images mirror params.*_image in ../../nextflow.config —
# keep this list in sync if you bump a pin there.
set -euo pipefail

# Shared cache on the NFS volume (must equal apptainer.cacheDir in the slurm profile).
export APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-/data/apptainer-cache}"
mkdir -p "$APPTAINER_CACHEDIR"

IMAGES=(
  "docker://cellprofiler/cellprofiler:4.2.8"
  "docker://ghcr.io/jakobhuuse/deepprofiler:0.5.1"
  "docker://cytomining/pycytominer:1.5.1_260603"
  "docker://ghcr.io/jakobhuuse/cytopipe:latest"
)

for img in "${IMAGES[@]}"; do
  sif="$APPTAINER_CACHEDIR/$(echo "${img#docker://}" | tr '/:' '--').sif"
  echo ">> pulling $img -> $sif"
  apptainer pull --force "$sif" "$img"
done

echo
echo "Done. Layer blobs + SIFs cached under $APPTAINER_CACHEDIR."
echo "Nextflow builds its own SIF filenames on first use; this primes the layer cache so that"
echo "build is fast. The definitive warm-up is a testdata run:  nextflow run ... -profile slurm"
