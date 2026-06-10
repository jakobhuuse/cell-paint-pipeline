#!/usr/bin/env bash
#SBATCH --job-name=cytopipe
#SBATCH --output=cytopipe-%j.log
#SBATCH --time=24:00:00
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
# STUB: this job only runs the Nextflow head process; per-stage resources are requested by
# Nextflow itself via the SLURM executor. Tune walltime/mem for your cluster.

set -euo pipefail

# TODO: adjust to your site's module names.
module load nextflow
module load apptainer

# Apptainer .sif cache (see .env.example APPTAINER_CACHEDIR).
export APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-/scratch/$USER/apptainer}"
mkdir -p "$APPTAINER_CACHEDIR"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

nextflow run "$REPO_ROOT/workflow/main.nf" \
    -profile slurm \
    -params-file "$REPO_ROOT/conf/params.yaml" \
    -resume
