# Deployment (HPC: SLURM + Apptainer)

## 1. Build/convert images

On a machine with Docker, build the two images we own and push them to a registry your
cluster can reach (see [../containers/README.md](../containers/README.md)). Then on the
cluster, materialise all four as Apptainer `.sif` files:

```bash
export APPTAINER_CACHEDIR=/scratch/$USER/apptainer
bash deploy/apptainer/build.sh
```

## 2. Configure

- Copy `.env.example` → `.env` and set the `*_IMAGE` tags + `APPTAINER_CACHEDIR`.
- Copy `conf/params.example.yaml` → `conf/params.yaml` and fill in inputs
  (`input_dir`, `cppipe`, `platemap`, …).

## 3. Submit

```bash
sbatch deploy/slurm/nextflow.slurm
```

A single Nextflow "head" job is submitted; Nextflow then submits one SLURM job per stage
task (per plate) via its `slurm` executor, scaling out across the cluster. `-resume` makes
re-runs skip completed work.

## TB-scale notes (TODO)

- Point Nextflow `workDir` at fast scratch, not `$HOME`.
- Tune per-process `cpus`/`memory`/`time` in `workflow/nextflow.config` (placeholders now).
- The DeepProfiler stage needs GPUs — uncomment the `withLabel: gpu` clause in the `slurm`
  profile and set the correct partition/`--gres`.
- Consider object storage (`s3://…`) for inputs/outputs; CytoTable and Nextflow both
  support remote paths.
