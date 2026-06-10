# cytopipe — cell-painting feature-extraction pipeline

A pipeline that turns raw microscopy images of perturbed cells into per-perturbation
feature profiles, designed to scale to TB-sized datasets on an HPC cluster.

> ⚠️ Skeleton / work in progress — structure and stubs only, no working stage logic yet.

## Data flow

```text
raw images
  ├─► CellProfiler  (traditional CV)  ──► image-based measurements (SQLite/CSV)
  │                                       └─ segmentation + metadata feed DeepProfiler
  └─► DeepProfiler  (deep learning)   ──► single-cell embeddings (.npz)
            │
            ▼
       CytoTable   ──► merged single-cell features (parquet)     [this repo: `cytopipe`]
            │
            ▼
      pycytominer ──► annotate → normalize → feature-select → aggregate (well / consensus)
```

## Architecture

- **Nextflow** orchestrates the DAG and launches every stage as a container — Docker
  locally (`-profile standard`), Apptainer on HPC (`-profile slurm`). It also stages files
  between stages.
- **Four container images:**
  | Stage | Image | Source |
  |-------|-------|--------|
  | CellProfiler | `cellprofiler/cellprofiler:4.2.8` | official, pinned |
  | DeepProfiler | `…/deepprofiler` | built here (`containers/deepprofiler/`, GPU/TF) |
  | pycytominer | `cytomining/pycytominer` | official, pinned (built-in CLI) |
  | cytopipe | `…/cytopipe` | built here (`containers/cytopipe/`, our code) |
- **`cytopipe`** (this Python package) is the data-management/glue layer built on
  **CytoTable**. It is the only code we write. Its CLI exposes:
  - `cytopipe convert` — CytoTable conversion of image-tool output → single-cell parquet
  - `cytopipe bridge` — CellProfiler → DeepProfiler metadata/segmentation handoff
  CellProfiler, DeepProfiler, and pycytominer run via their own images' native entrypoints.

## Develop locally

```bash
uv sync                       # install deps (incl. dev: ruff, pytest)
uv run ruff check .           # lint
uv run ruff format .          # format
uv run pytest                 # tests
uv run cytopipe --help        # CLI
```

## Run the pipeline

```bash
# Local (Docker)
nextflow run workflow/main.nf -profile standard -params-file conf/params.yaml

# HPC (SLURM + Apptainer)
sbatch deploy/slurm/nextflow.slurm
```

See [conf/README.md](conf/README.md) for the inputs you must supply (CellProfiler `.cppipe`,
DeepProfiler config/checkpoint, platemap) and [deploy/README.md](deploy/README.md) for HPC
setup.
