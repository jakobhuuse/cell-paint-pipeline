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
  (image-tool output → single-cell parquet), and `cytopipe bridge`
  (CellProfiler → DeepProfiler metadata handoff). CellProfiler, DeepProfiler, and pycytominer run
  via their own images' native entrypoints.

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

# Cluster (SLURM + Apptainer), see deploy/README.md
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
command line with `--<name> <value>` (or in a `-params-file`).

### Project

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--pipeline` | `deepprofiler` | Which branch to run: `deepprofiler` or `cellprofiler`. |
| `--input_dir` | `${projectDir}/tests/data` | Root of the raw images, and must also contain `platemap.csv`. |
| `--plate_glob` | `*/*` | Glob (relative to `input_dir`) selecting per-plate image directories. |
| `--outdir` | `results` | Where published outputs and run reports land. |

### CellProfiler

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--cellprofiler_image` | `cellprofiler/cellprofiler:4.2.8` | CellProfiler container image. |
| `--qc_cppipe` | `conf/cellprofiler/1_QC.cppipe` | Quality-control pipeline. |
| `--illum_cppipe` | `conf/cellprofiler/2_IllumCorrection.cppipe` | Illumination-correction pipeline. |
| `--analysis_cppipe` | `conf/cellprofiler/3_JUMP_analysis.cppipe` | Feature-extraction (JUMP analysis) pipeline. |
| `--nuclei_cppipe` | `conf/cellprofiler/nuclei.cppipe` | Nuclei segmentation (also used by the DeepProfiler branch). |
| `--cellprofiler_chunk_size` | `50` | Images per CellProfiler chunk, trading parallelism against per-task memory. |

### DeepProfiler

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--deepprofiler_image` | `ghcr.io/jakobhuuse/deepprofiler:0.5.1` | DeepProfiler container image. |
| `--deepprofiler_model` | `conf/deepprofiler/model.hdf5` | Trained model checkpoint. |
| `--deepprofiler_config` | `conf/deepprofiler/config.json` | DeepProfiler configuration. |
| `--deepprofiler_embedding_dim` | `672` | Embedding length, which sets the `efficientnet_1..N` feature names passed to pycytominer. |

### cytopipe

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--cytopipe_image` | `ghcr.io/jakobhuuse/cytopipe:1.0.0` | cytopipe container image. |

### pycytominer

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--pycytominer_image` | `cytomining/pycytominer:1.5.1_260603` | pycytominer container image. |
| `--pycytominer_aggregate_strata_dp` | `Metadata_Plate,Metadata_Well,Metadata_Compound` | Grouping columns for well-level aggregation (DeepProfiler branch). |
| `--pycytominer_aggregate_strata_cp` | `Metadata_Plate,Metadata_Well` | Grouping columns for well-level aggregation (CellProfiler branch). |
| `--pycytominer_annotate_join_on` | `Metadata_DestinationWell,Metadata_Well` | Columns to join the platemap (first) onto the profiles (second) during annotation (CellProfiler branch). |
| `--pycytominer_normalize_samples` | `Metadata_Compound == 'DMSO'` | Query selecting the control samples normalization is fit against. |
| `--pycytominer_feature_select_ops` | `variance_threshold,correlation_threshold,blocklist` | Feature-selection operations (CellProfiler branch). |
| `--pycytominer_consensus_columns` | `Metadata_Compound` | Grouping columns for the consensus (per-perturbation) profile. |

### Profiles

| Profile | Runtime | Use |
|---------|---------|-----|
| `standard` | Docker (CPU) | Local development, the default. |
| `gpu` | Docker + `--gpus all` | Local runs with a GPU for DeepProfiler inference. |
| `slurm` | Apptainer on SLURM | HPC. See [deploy/README.md](deploy/README.md). |

## Outputs

Everything is published under `--outdir`, namespaced by branch (`<pipeline>/…`) so the two never
collide:

- `<pipeline>/qc/<plate_id>/`: per-plate QC reports.
- `<pipeline>/raw/`, `<pipeline>/normalized/`: single-cell and normalized profiles.
- `<pipeline>/`: feature-selected (CellProfiler only), consensus profiles, and report figures.
- `nextflow/<timestamp>/`: Nextflow `trace.txt`, `report.html`, and `timeline.html`.

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
a GPU):

```bash
nextflow run . -profile standard --pipeline cellprofiler
nextflow run . -profile gpu      --pipeline deepprofiler
```

You can also validate config and syntax without running anything (the CI `lint` job):

```bash
nextflow lint .
nextflow config -profile standard
```

## Deployment

For provisioning a self-managed SLURM + Apptainer cluster on OpenStack (head + compute nodes,
shared `/data` over NFS), see [deploy/README.md](deploy/README.md).

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
