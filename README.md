# cell-paint-pipeline — cell-paint feature-extraction pipeline

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
       CytoTable   ──► merged single-cell features (parquet)     [cytopipe: separate repo]
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
  | DeepProfiler | `…/deepprofiler` | thin image over the [`deepprofiler` PyPI package](https://pypi.org/project/deepprofiler/), built here (`containers/deepprofiler/`, GPU/TF) |
  | pycytominer | `cytomining/pycytominer` | official, pinned (built-in CLI) |
  | cytopipe | `ghcr.io/jakobhuuse/cytopipe` | built from the [cytopipe repo](https://github.com/jakobhuuse/cytopipe) (our code) |

- **`cytopipe`** is the data-management/glue layer built on **CytoTable** — the only code we
  write. It lives in its own repo ([jakobhuuse/cytopipe](https://github.com/jakobhuuse/cytopipe))
  and is consumed here purely as a container image, set via `params.cytopipe_image`. Its CLI
  exposes `cytopipe convert` (image-tool output → single-cell parquet) and `cytopipe bridge`
  (CellProfiler → DeepProfiler metadata handoff). CellProfiler, DeepProfiler, and pycytominer
  likewise run via their own images' native entrypoints.

## Run the pipeline

The CellProfiler and DeepProfiler branches are independent workflows — `main.nf` dispatches
to one via `--pipeline` (`deepprofiler` (default) or `cellprofiler`).

```bash
# Local (Docker)
nextflow run . -profile standard --pipeline deepprofiler
nextflow run . -profile standard --pipeline cellprofiler

# Cluster (SLURM + Apptainer) — see deploy/README.md
nextflow run . -profile slurm --pipeline deepprofiler \
    --input_dir /data/input --outdir /data/results

# Remote (pulled straight from GitHub, pinned to a release)
nextflow run jakobhuuse/cell-paint-pipeline -r v1.0.0 -profile standard --pipeline deepprofiler
```

See [conf/README.md](conf/README.md) for the inputs you must supply (CellProfiler `.cppipe`,
DeepProfiler config/checkpoint, platemap) and [deploy/README.md](deploy/README.md) for OpenStack /
SLURM setup.

## Tests

All [nf-test](https://www.nf-test.com) tests live in `tests/`. nf-test only supports tag
*inclusion*, so the fast/slow split is by tag: fast tests carry `fast`, end-to-end ones `integration`.

```bash
curl -fsSL https://code.askimed.com/install/nf-test | bash   # once, installs ./nf-test

./nf-test test --tag fast                        # fast: Groovy helpers + --pipeline dispatch, no Docker (this is what CI runs)
./nf-test test --tag integration -profile standard   # slow: runs each branch end-to-end against test/ through real containers
./nf-test test                                   # everything
```

The fast tier runs on every push/PR via GitHub Actions ([.github/workflows/ci.yml](.github/workflows/ci.yml)),
alongside `nextflow lint`. The integration tier needs the full container stack (and a GPU for
DeepProfiler), so it is not wired into CI — run it locally or on a self-hosted runner.
