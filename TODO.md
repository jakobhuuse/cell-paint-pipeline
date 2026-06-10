# Next steps — from skeleton to working pipeline

A step-by-step path to get this running. It's ordered so each step builds on the last.
You already know **CellProfiler, DeepProfiler, Typer, uv, and Docker** — the new pieces are
**Nextflow, CytoTable, pycytominer,** and (much later) **Apptainer**. Each is explained the
first time it shows up. Take it one phase at a time; you don't need the whole thing at once.

The default path is **CellProfiler → CytoTable → pycytominer**. DeepProfiler is an optional
branch you can ignore until Phase 5.

---

## Phase 0 — Dev environment (do this once)

> 📘 **Nextflow** is the "conductor": it runs each stage in a container, passes files
> between stages, and runs many plates in parallel. It needs a Linux-like shell, so on
> Windows we run everything inside **WSL2** (Ubuntu). Bonus: inside WSL the Python deps
> import cleanly (they don't on native Windows).

- [ ] Install **WSL2 + Ubuntu** (`wsl --install` in PowerShell) and enable Docker Desktop's
      "WSL integration" for the Ubuntu distro.
- [ ] Open an Ubuntu terminal. From there, install Java + Nextflow:
      `curl -s https://get.nextflow.io | bash` then move `nextflow` onto your `PATH`.
- [ ] Confirm the basics work in WSL:
  ```bash
  cd /mnt/c/Users/jakob/Documents/SINTEF/project
  uv sync
  uv run pytest        # 3 tests should pass
  nextflow -version
  docker run hello-world
  ```

## Phase 1 — See the pipeline "run" with no real tools

This proves the wiring works before you build images or touch data.

- [ ] Make two fake plate folders and do a **stub run** (every stage just echoes the command
      it *would* run — see the `stub:` blocks in `workflow/modules/*.nf`):
  ```bash
  mkdir -p testdata/plate_001 testdata/plate_002
  nextflow run workflow/main.nf -stub-run \
    -profile standard --input_dir ./testdata -process.container=false
  ```
- [ ] You should see CELLPROFILER → CYTOTABLE → PYCYTOMINER run for *both* plates. If so,
      the DAG is sound. 🎉

## Phase 2 — Build/pull the container images

> 📘 The pipeline uses 4 images. Two are public, one you build, one you skip for now.

- [ ] Pull the public ones:
  ```bash
  docker pull cellprofiler/cellprofiler:4.2.8
  docker pull cytomining/pycytominer:latest
  ```
- [ ] Build **our** image (the CytoTable glue, `cytopipe`):
  ```bash
  docker build -t cytopipe:dev -f containers/cytopipe/Dockerfile .
  ```
- [ ] (Skip DeepProfiler's image for now — `run_deepprofiler` is `false` by default.)

## Phase 3 — Implement the CytoTable step (the core glue)

> 📘 **CytoTable** turns CellProfiler's output (a `.sqlite` file of per-compartment
> measurements) into a single **single-cell parquet** table that pycytominer can read. Our
> `cytopipe convert` command is a thin wrapper around it.

- [ ] Open [src/cytopipe/convert.py](src/cytopipe/convert.py). Right now `run_convert` raises
      `NotImplementedError`. Un-comment the `cytotable.convert(...)` call (the arguments are
      already filled in) and delete the `raise`.
- [ ] Test it directly (fast, no Docker/Nextflow needed — run in WSL):
  ```bash
  uv run cytopipe convert --source some_output.sqlite --dest out.parquet
  ```
      Use a small CellProfiler `.sqlite` you already have, or make a tiny one in Phase 4.
- [ ] Rebuild the image so Nextflow picks up your change:
      `docker build -t cytopipe:dev -f containers/cytopipe/Dockerfile .`

## Phase 4 — Provide your real inputs & run one plate for real

- [ ] **CellProfiler pipeline:** in the CellProfiler GUI, build (or adapt) your `.cppipe`.
      The one rule for this pipeline: the **export** must be **ExportToDatabase → SQLite**
      (keep compartment names Cells / Cytoplasm / Nuclei). Save it to
      `conf/cellprofiler/pipeline.cppipe`.
- [ ] **Platemap:** create `conf/platemap.csv` mapping each well to its perturbation/metadata
      (pycytominer uses this to annotate).
- [ ] **Fill in params:** `cp conf/params.example.yaml conf/params.yaml` and set `input_dir`,
      `cppipe`, and `platemap`.
- [ ] **Check the pycytominer step:** open [workflow/modules/pycytominer.nf](workflow/modules/pycytominer.nf)
      and confirm the `annotate → normalize → feature_select → aggregate` flags match the
      `cytomining/pycytominer` CLI for your data (column names, methods).
      > 📘 **pycytominer** does 5 standard operations on profiles: *annotate* (attach platemap
      > metadata), *normalize*, *feature_select*, *aggregate* (e.g. per well), *consensus*.
- [ ] **Run it on one plate:**
  ```bash
  nextflow run workflow/main.nf -profile standard \
    -params-file conf/params.yaml --cytopipe_image cytopipe:dev
  ```
- [ ] Check `results/pycytominer/<plate>/` for the final profile parquet.

## Phase 5 — (Optional) Turn on the DeepProfiler branch

Only if you want the deep-learning embeddings too. This is the fiddly part because
DeepProfiler is strict about its project-folder layout.

- [ ] Put your DeepProfiler `config.json` at `conf/deepprofiler/config.json` and the model
      weights (e.g. `Cell_Painting_CNN_v1.hdf5` from Zenodo `10.5281/zenodo.7114558`) under
      `conf/deepprofiler/checkpoint/`.
- [ ] Implement [src/cytopipe/bridge.py](src/cytopipe/bridge.py) — it builds the `index.csv`
      DeepProfiler needs from CellProfiler output + the platemap.
- [ ] Flesh out [workflow/modules/deepprofiler.nf](workflow/modules/deepprofiler.nf) so it
      assembles DeepProfiler's `inputs/`/`outputs/` project layout (config + index.csv +
      checkpoint) before calling `profile`. *(Ask Claude to help here — it's the trickiest
      module.)*
- [ ] Build the DeepProfiler image: `docker build -t deepprofiler:dev containers/deepprofiler`
      (you'll need to pin a Git SHA in the Dockerfile first).
- [ ] Run with `--run_deepprofiler true`.

## Phase 6 — (Much later) Run on the HPC cluster

> 📘 **Apptainer** is "Docker for HPC" — clusters usually don't allow Docker, so the same
> images get converted to `.sif` files. **SLURM** is the cluster's job scheduler. You don't
> need any of this for local development.

- [ ] Read [deploy/README.md](deploy/README.md).
- [ ] On the cluster, convert images to `.sif` with `deploy/apptainer/build.sh`.
- [ ] Submit with `sbatch deploy/slurm/nextflow.slurm` (uses `-profile slurm`). Nextflow then
      submits one cluster job per plate-stage automatically.

---

## Handy commands (run in WSL)

```bash
uv run ruff check . && uv run ruff format .   # lint + format
uv run pytest                                 # tests
uv run cytopipe --help                        # CLI
nextflow run workflow/main.nf -profile standard -stub-run --input_dir ./testdata -process.container=false
```

## When you get stuck

- DAG/plumbing questions → it's Nextflow; the logic lives in `workflow/`.
- "How do I convert CP output?" → CytoTable; logic in `src/cytopipe/convert.py`.
- "How do I shape the final profiles?" → pycytominer; flags in `workflow/modules/pycytominer.nf`.
- Anything DeepProfiler/CellProfiler-specific → you already know these better than the glue!
