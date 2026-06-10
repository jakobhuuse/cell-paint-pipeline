# Configuration & user-supplied inputs

Copy `params.example.yaml` → `params.yaml` and edit. The pipeline also needs these
user-supplied files (not committed — they're data/experiment-specific):

| File | Used by | Notes |
|------|---------|-------|
| `cellprofiler/pipeline.cppipe` | CellProfiler | Your segmentation + measurement pipeline. Drop it in `conf/cellprofiler/`. |
| `platemap.csv` | pycytominer (annotate) | Maps wells → perturbation/metadata. |
| `deepprofiler/config.json` | DeepProfiler | Channels, model, train/val split. Only for the deep-learning branch. |
| `deepprofiler/checkpoint/…` | DeepProfiler | Pretrained weights (e.g. Cell Painting CNN). |

`.gitkeep` files mark the expected drop locations.
