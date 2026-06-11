include { CELLPROFILER } from './modules/cellprofiler.nf'
include { DEEPPROFILER } from './modules/deepprofiler.nf'
include { CYTOTABLE    } from './modules/cytotable.nf'
include { PYCYTOMINER  } from './modules/pycytominer.nf'

// --- Parameters (override via -params-file conf/params.yaml) ---
params.input_dir  = null          // experiment root of raw image data
params.plate_glob = '*/*'          // plate dirs relative to input_dir: <date>/<plate>
params.cppipe     = null          // CellProfiler pipeline (.cppipe)
params.platemap   = null          // platemap CSV
params.dp_config  = null          // DeepProfiler config.json
params.run_deepprofiler = false   // toggle the deep-learning branch

workflow {
    if( !params.input_dir ) error "Set --input_dir (experiment root of raw images)."

    // One work item per plate directory — Nextflow fans these out across the cluster.
    // Raw layout: <input_dir>/<date>/<plate>/TimePoint_*/*.tif, so a plate sits at
    // `${params.plate_glob}` (default '*/*') and holds one or more TimePoint_* subdirs.
    plates = channel.fromPath("${params.input_dir}/${params.plate_glob}", type: 'dir')
        .map { dir -> tuple(dir.name, dir) }   // (plate_id, plate_dir)

    // Stage 1: CellProfiler (image-based measurements + per-site outputs).
    CELLPROFILER(plates, file(params.cppipe ?: 'NO_CPPIPE'))

    // Stage 2: CytoTable -> single-cell parquet (CellProfiler branch).
    CYTOTABLE(CELLPROFILER.out.measurements)

    // Stage 3: pycytominer -> aggregated/normalized profiles.
    PYCYTOMINER(CYTOTABLE.out.single_cell, file(params.platemap ?: 'NO_PLATEMAP'))

    // Optional deep-learning branch (off by default).
    if( params.run_deepprofiler ) {
        DEEPPROFILER(CELLPROFILER.out.dp_metadata, file(params.dp_config ?: 'NO_DPCONFIG'))
    }
}
