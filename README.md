# cell-paint-pipeline

[![CI](https://github.com/jakobhuuse/cell-paint-pipeline/actions/workflows/ci.yml/badge.svg)](https://github.com/jakobhuuse/cell-paint-pipeline/actions/workflows/ci.yml)
[![Nextflow](https://img.shields.io/badge/nextflow-%E2%89%A526.04-23aa62.svg)](https://www.nextflow.io/)

A Nextflow pipeline that turns raw cell-painting microscopy images of perturbed cells into
per-perturbation feature profiles. It scales from a laptop (Docker) to a SLURM/Apptainer HPC
cluster (TB-sized datasets) without changing the workflow, only the profile.

Two independent feature-extraction branches are available. Pick one per run with `--pipeline`:

- **`deepprofiler`** (default): deep-learning single-cell embeddings.
- **`cellprofiler`**: classical computer-vision measurements.

Both start from the same raw images and converge on well- and consensus-level profiles, but the
stages in between differ (see the diagram below).

## Data flow

`--pipeline` selects one of two independent branches. Only one runs per invocation, and their
outputs are namespaced under `<pipeline>/` so they never collide.

![Data flow diagram](docs/dataflow.drawio.svg)

## Architecture

- **Nextflow** orchestrates the DAG and launches every stage as a container. Docker runs it
  locally (`-profile standard` / `-profile gpu`), Apptainer runs it on HPC (`-profile slurm`). It
  also stages files between stages.
- **Four container images** (all pinned, and you can override any of them with the matching
  `*_image` param):

  | Stage | Default image | Source |
  |-------|---------------|--------|
  | CellProfiler | `cellprofiler/cellprofiler:4.2.8` | official, pinned |
  | DeepProfiler | `ghcr.io/jakobhuuse/deepprofiler:0.5.1` | built from the Dockerfile in our [DeepProfiler fork](https://github.com/jakobhuuse/DeepProfiler) (GPU/TF), published to GHCR |
  | pycytominer | `cytomining/pycytominer:1.5.1_260603` | official, pinned (built-in CLI) |
  | cytopipe | `ghcr.io/jakobhuuse/cytopipe:1.0.0` | built from the [cytopipe repo](https://github.com/jakobhuuse/cytopipe) (our code) |

- **`cytopipe`** is the data-management/glue layer. It lives in its own repo ([jakobhuuse/cytopipe](https://github.com/jakobhuuse/cytopipe))
  and is consumed here purely as a container image (`--cytopipe_image`). Its CLI exposes
  `cytopipe loaddata` (build CellProfiler LoadData CSVs + chunking), `cytopipe convert`
  (image-tool output → single-cell parquet), `cytopipe bridge`
  (CellProfiler → DeepProfiler metadata handoff), and `cytopipe aggregate` (well-level median
  profiles, a memory-bounded DuckDB replacement for `pycytominer aggregate`). CellProfiler,
  DeepProfiler, and the remaining pycytominer steps run via their own images' native entrypoints.

## Installation

The pipeline runs directly from GitHub, so you do not need to clone it for a normal run:

```bash
# Remote (pulled straight from GitHub, pinned to a release)
nextflow run jakobhuuse/cell-paint-pipeline -r v1.0.0 -profile standard --pipeline deepprofiler
```

For local development, clone the repo and run from the checkout (`nextflow run .`) as shown under
[Usage](#usage).

### Requirements

- Nextflow 26.04 or newer.
- Docker (local) or Apptainer (HPC).
- A GPU is optional but strongly recommended for the DeepProfiler branch.

## Usage

```bash
# Local (Docker), runs against the bundled tests/data by default
nextflow run . -profile standard --pipeline deepprofiler
nextflow run . -profile standard --pipeline cellprofiler

# Local with a GPU for the DeepProfiler inference step
nextflow run . -profile gpu --pipeline deepprofiler

# Your own data
nextflow run . -profile standard --pipeline cellprofiler \
    --input_dir /path/to/images --outdir /path/to/results

# Cluster (SLURM + Apptainer), see the Deployment section below
nextflow run . -profile slurm --pipeline deepprofiler \
    --input_dir /data/input --outdir /data/results
```

## Inputs

Point `--input_dir` at a directory laid out as `<input_dir>/<plate_glob>/…images…`, plus a
platemap. With the default `--plate_glob '*/*'`, plates live two levels down (e.g.
`tests/data/2025-12-16/26159/`). Requirements:

- **Images**: `.tif` files under each plate directory (`*_thumb` thumbnails are ignored).
- **`platemap.csv`**: directly under `--input_dir`, mapping wells to compounds/metadata.
- **CellProfiler pipelines** (`.cppipe`): bundled in [conf/cellprofiler/](conf/cellprofiler/),
  covering QC, illumination correction, JUMP analysis, and nuclei segmentation. Swap via the
  `*_cppipe` params. The `deepprofiler` branch still uses `nuclei_cppipe` for segmentation.
- **DeepProfiler config + model**: bundled in [conf/deepprofiler/](conf/deepprofiler/)
  (`config.json`, `model.hdf5`). Override with `--deepprofiler_config` / `--deepprofiler_model`.

## Parameters

All parameters have defaults in [nextflow.config](nextflow.config). Override any of them on the
command line with `--<name> <value>` (or in a `-params-file`). Full reference, grouped by tool, in
[docs/parameters.md](docs/parameters.md).

The two most commonly overridden.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--pipeline` | `deepprofiler` | Which branch to run: `deepprofiler` or `cellprofiler`. |
| `--input_dir` | `${projectDir}/tests/data` | Root of the raw images, and must also contain `platemap.csv`. |

### Profiles

| Profile | Runtime | Use |
|---------|---------|-----|
| `standard` | Docker (CPU) | Local development, the default. |
| `gpu` | Docker + `--gpus all` | Local runs with a GPU for DeepProfiler inference. |
| `slurm` | Apptainer on SLURM | HPC. See [Deployment](#deployment). |

## Outputs

Everything is published under `--outdir`, namespaced by branch (`<pipeline>/…`) so the two never
collide:

- `<pipeline>/qc/<plate_id>/`: per-plate QC reports.
- `<pipeline>/raw/`, `<pipeline>/normalized/`: single-cell and normalized profiles.
- `<pipeline>/`: feature-selected (CellProfiler only), consensus profiles, and report figures.
- `nextflow/<timestamp>/`: Nextflow `trace.txt`, `report.html`, and `timeline.html`.

With `--profiling false`, only the QC reports and single-cell `raw/` profiles are produced; the
aggregation, normalization, cohort, and report outputs are skipped.

## Deployment

The `slurm` profile expects a SLURM cluster with Apptainer on every node and a shared `/data`. Building that cluster is a separate concern and lives in its own repo, [openstack-orchestrator](https://gitlab.sintef.no/jakob.huuse/openstack-orchestrator), which stands one up on an OpenStack tenant from a single hand-created head node. Its README is the runbook.

Once the cluster is up, no clone is needed: Nextflow pulls this pipeline straight from GitHub and resolves its bundled `conf/` from inside the pulled copy. Give each experiment its own folder under `/data`, stage raw images plus `platemap.csv` into `input/`, and launch from inside that folder under `tmux`:

```bash
tmux new -s <experiment>
cd /data/<experiment>

nextflow run jakobhuuse/cell-paint-pipeline -profile slurm --input_dir input
nextflow run jakobhuuse/cell-paint-pipeline -profile slurm --pipeline cellprofiler --input_dir input
```

`workDir` is the shared `/data/work` with `cache = 'lenient'`, so `-resume` from the same experiment folder cheaply re-uses completed tasks.

## Testing

[nf-test](https://www.nf-test.com) unit tests live in [tests/](tests/) and cover the Groovy helpers
and `--pipeline` dispatch. They need no Docker, finish in seconds, and run in CI on every push and
PR alongside `nextflow lint` (see [.github/workflows/ci.yml](.github/workflows/ci.yml)):

```bash
curl -fsSL https://code.askimed.com/install/nf-test | bash   # once, installs ./nf-test
./nf-test test --tag fast
```

There are no automated end-to-end tests. To exercise the full stack, run each branch locally
against the bundled `tests/data` dataset (this pulls every image, and the DeepProfiler branch wants
a GPU). The fixture has too few wells for the cohort profiling steps (correlation-based feature
selection and consensus are undefined on a handful of samples), so disable the profiling tail with
`--profiling false`; the run then stops at single-cell parquet:

```bash
nextflow run . -profile standard --pipeline cellprofiler --profiling false
nextflow run . -profile gpu      --pipeline deepprofiler --profiling false
```

You can also validate config and syntax without running anything (the CI `lint` job):

```bash
nextflow lint .
nextflow config -profile standard
```

## Support

Open an issue on the [issue tracker](https://github.com/jakobhuuse/cell-paint-pipeline/issues) for
questions or bug reports.

## Acknowledgments

This pipeline stands on [Nextflow](https://www.nextflow.io/),
[CellProfiler](https://cellprofiler.org/),
[DeepProfiler](https://github.com/cytomining/DeepProfiler),
[pycytominer](https://github.com/cytomining/pycytominer), and
[cytopipe](https://github.com/jakobhuuse/cytopipe).

## License

Licensed under the [BSD 3-Clause License](LICENSE). Copyright (c) 2026 Jakob Huuse, SINTEF Industri.
