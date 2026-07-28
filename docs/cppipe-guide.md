# Bringing your own CellProfiler pipeline (.cppipe)

Back to [README](../README.md).

Nextflow uses 4 different cellprofiler pipelines for analysis. Below is a list over what each pipeline does, as well as the flag you can use to override it.

| Flag | Replaces | What it does | Used by |
|------|----------|--------------|---------|
| `--qc_cppipe` | `1_QC.cppipe` | Per-image quality-control measurements. | `--pipeline qc` only (branch-agnostic) |
| `--illum_cppipe` | `2_IllumCorrection.cppipe` | Calculates the illumination-correction function each plate needs. | CellProfiler branch only |
| `--analysis_cppipe` | `3_JUMP_analysis.cppipe` | The main feature-extraction (JUMP analysis) pipeline. | CellProfiler branch only |
| `--nuclei_cppipe` | `nuclei.cppipe` | Nuclei segmentation. | DeepProfiler branch only |

## Modifying the pipelines

It's heavily recommended to download the pipeline you want to change from [conf/cellprofiler/](https://github.com/jakobhuuse/cell-paint-pipeline/tree/main/conf/cellprofiler) on GitHub and just adjust its module parameters, rather than building one from scratch. Open the downloaded `.cppipe` file in CellProfiler, make your changes, and save it under a new name.

Point the matching flag at your saved file to use it instead of the bundled default. See the example below.

```bash
nextflow run jakobhuuse/cell-paint-pipeline -profile standard --pipeline cellprofiler \
    --analysis_cppipe /path/to/your/3_JUMP_analysis.cppipe
```

## Creating your own pipeline

If adjusting parameters isn't enough, here's what a pipeline built from scratch has to accept and produce to keep working with the rest of the run.

### Input

Regardless of what's inside your `.cppipe`, Nextflow invokes CellProfiler headless the same way every time.

```bash
cellprofiler -c -r -p <your.cppipe> --data-file <loaddata.csv> -i <images-folder> -o <output-folder>
```

Your pipeline's first module has to be a `LoadData` module reading whatever `--data-file` points to, not an `Images`/`NamesAndTypes` chain reading files off disk directly. That CSV always has `Metadata_Plate`, `Metadata_Well`, `Metadata_Site`, and one `Image_FileName_Orig<channel>` column per channel, for the five Cell Painting channels, `AGP`, `DNA`, `ER`, `Mito`, `RNA`. Load and refer to images under those exact `Orig<channel>` names.

### Output

- **`--qc_cppipe`.** Mostly free-form, its whole output folder is published as-is under `qc/<plate>/`. Two paths are read by name, though. A per-well `QCb3/<Plate>_<Well>/Image.csv` (an `ExportToSpreadsheet` module exporting all measurements, including `ImageQuality_PowerLogLogSlope_Orig<Channel>`) and a per-site `Overlays/<Plate>_<Well>_<Site>_overlay.png` composite (a `SaveImages` module). `cytopipe qc review` scans both to build the image-review gallery. Get either wrong and the gallery just comes up empty rather than failing loudly.
- **`--illum_cppipe`.** Must save one illumination-correction image per channel, named `IllumAGP`, `IllumDNA`, `IllumER`, `IllumMito`, `IllumRNA`. `3_JUMP_analysis.cppipe`'s `CorrectIlluminationApply` modules load them back by those exact names.
- **`--analysis_cppipe`.** Must end in an `ExportToDatabase` module writing a SQLite file named `measurements.sqlite`, exporting the `Cells`, `Cytoplasm`, and `Nuclei` object tables, with `Plate` and `Well` set as the plate and well metadata. `pycytominer` reads those object and column names afterward.

    Adding new measurements is safe as long as they attach to one of those three objects. Any `Measure*` module you add that measures `Cells`, `Cytoplasm`, or `Nuclei` has its output columns exported by `ExportToDatabase` automatically (it exports every measurement for the selected objects, not a fixed list), carried through unchanged by `cytopipe`'s SQLite-to-parquet conversion, and picked up by `pycytominer`'s feature inference downstream. No flag, config, or other file needs to change for new per-object measurements to reach `results/`.

    This does **not** cover two other kinds of change, a whole-image measurement not attached to any of the three objects (only `Image_FileName_*` columns survive the parquet conversion for `Per_Image` today), or a brand-new object/compartment beyond `Cells`/`Cytoplasm`/`Nuclei` (the SQLite-to-parquet join is a fixed three-way join). Either of those needs a change in `cytopipe`, not just a `.cppipe` edit.
- **`--nuclei_cppipe`.** Must produce a per-site nuclei-locations file at `locations/<well>-<site>-Nuclei.csv` (an `ExportToSpreadsheet` module exporting just `Nuclei|Location_Center_X`/`Location_Center_Y`), plus a flat `Image.csv` at the output root carrying at least `Metadata_Plate`/`Well`/`Site` and `FileName_Orig<channel>` columns. `cytopipe`'s DeepProfiler bridge reads both by these exact names to hand nuclei coordinates to DeepProfiler.

Get a filename or column name wrong and the run typically doesn't fail inside CellProfiler, it fails a step or two later inside `cytopipe` or `pycytominer`, further from where the actual mistake was made.
