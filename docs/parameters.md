# Parameters

Back to [README](../README.md).

All parameters have defaults in [nextflow.config](../nextflow.config). Override any of them on the
command line with `--<name> <value>` (or in a `-params-file`).

## Project

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--pipeline` | `deepprofiler` | Which branch to run: `deepprofiler` or `cellprofiler`. |
| `--profiling` | `true` | Run the profiling tail (aggregate, normalize, feature selection/consensus, report). Set `false` for tiny fixtures, where the cohort statistics are undefined and the run would abort; it then stops at single-cell parquet. |
| `--input_dir` | `${projectDir}/tests/data` | Root of the raw images, and must also contain `platemap.csv`. |
| `--plate_glob` | `*/*` | Glob (relative to `input_dir`) selecting per-plate image directories. |
| `--outdir` | `results` | Where published outputs and run reports land. |

## CellProfiler

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--cellprofiler_image` | `cellprofiler/cellprofiler:4.2.8` | CellProfiler container image. |
| `--qc_cppipe` | `conf/cellprofiler/1_QC.cppipe` | Quality-control pipeline. |
| `--illum_cppipe` | `conf/cellprofiler/2_IllumCorrection.cppipe` | Illumination-correction pipeline. |
| `--analysis_cppipe` | `conf/cellprofiler/3_JUMP_analysis.cppipe` | Feature-extraction (JUMP analysis) pipeline. |
| `--nuclei_cppipe` | `conf/cellprofiler/nuclei.cppipe` | Nuclei segmentation (also used by the DeepProfiler branch). |
| `--cellprofiler_chunk_size` | `50` | Images per CellProfiler chunk, trading parallelism against per-task memory. |

## DeepProfiler

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--deepprofiler_image` | `ghcr.io/jakobhuuse/deepprofiler:0.5.1` | DeepProfiler container image. |
| `--deepprofiler_model` | `conf/deepprofiler/model.hdf5` | Trained model checkpoint. |
| `--deepprofiler_config` | `conf/deepprofiler/config.json` | DeepProfiler configuration. |
| `--deepprofiler_embedding_dim` | `672` | Embedding length, which sets the `efficientnet_1..N` feature names passed to the aggregation and pycytominer steps. |

## cytopipe

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--cytopipe_image` | `ghcr.io/jakobhuuse/cytopipe:1.0.0` | cytopipe container image. |

## pycytominer

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--pycytominer_image` | `cytomining/pycytominer:1.5.1_260603` | pycytominer container image. |
| `--pycytominer_aggregate_strata_dp` | `Metadata_Plate,Metadata_Well,Metadata_Compound` | Grouping columns for well-level median aggregation, now run by `cytopipe aggregate` (DeepProfiler branch). |
| `--pycytominer_aggregate_strata_cp` | `Metadata_Plate,Metadata_Well` | Grouping columns for well-level median aggregation, now run by `cytopipe aggregate` (CellProfiler branch). |
| `--pycytominer_annotate_join_on` | `Metadata_DestinationWell,Metadata_Well` | Columns to join the platemap (first) onto the profiles (second) during annotation (CellProfiler branch). |
| `--pycytominer_normalize_samples` | `Metadata_Compound == 'DMSO'` | Query selecting the control samples normalization is fit against. |
| `--pycytominer_feature_select_ops` | `variance_threshold,correlation_threshold,blocklist` | Feature-selection operations (CellProfiler branch). |
| `--pycytominer_consensus_columns` | `Metadata_Compound` | Grouping columns for the consensus (per-perturbation) profile. |

## Profiles

| Profile | Runtime | Use |
|---------|---------|-----|
| `standard` | Docker (CPU) | Local development, the default. |
| `gpu` | Docker + `--gpus all` | Local runs with a GPU for DeepProfiler inference. |
| `slurm` | Apptainer on SLURM | HPC. See [Deployment](../README.md#deployment). |
