# Container images

The pipeline uses four images. Two are pinned official images (no Dockerfile needed); two
are built here.

| Stage | Image | Built here? |
|-------|-------|-------------|
| CellProfiler | `cellprofiler/cellprofiler:4.2.8` | No — official, pinned |
| pycytominer | `cytomining/pycytominer:<tag>` | No — official, pinned (built-in CLI) |
| DeepProfiler | `deepprofiler/Dockerfile` | Yes — no published image/PyPI release |
| cytopipe | `cytopipe/Dockerfile` | Yes — our CytoTable glue code |

## Build (local Docker)

```bash
docker build -t deepprofiler:dev containers/deepprofiler
docker build -t cytopipe:dev    -f containers/cytopipe/Dockerfile .
```

Tag/push to your registry and set the corresponding `*_IMAGE` variable in `.env`.

For HPC, convert these to Apptainer `.sif` images — see
[../deploy/apptainer/build.sh](../deploy/apptainer/build.sh).
