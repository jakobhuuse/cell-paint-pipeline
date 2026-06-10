#!/usr/bin/env nextflow

/*
 * Cell-painting feature-extraction pipeline.
 *
 *   CellProfiler ─┬─► CytoTable ─► pycytominer
 *                 └─► (bridge) ─► DeepProfiler
 *
 * STUB: processes are stub-only (see `stub:` blocks) — they echo the command they would
 * run so the DAG can be wired and tested with `-stub-run` before the real logic exists.
 * Fan-out across plates is sketched via the `plates` channel.
 */

nextflow.enable.dsl = 2

include { CELLPROFILER } from './modules/cellprofiler.nf'
include { DEEPPROFILER } from './modules/deepprofiler.nf'
include { CYTOTABLE    } from './modules/cytotable.nf'
include { PYCYTOMINER  } from './modules/pycytominer.nf'

// --- Parameters (override via -params-file conf/params.yaml) ---
params.input_dir  = null          // root of raw image data (per-plate subdirs)
params.outdir     = 'results'
params.cppipe     = null          // CellProfiler pipeline (.cppipe)
params.platemap   = null          // platemap CSV
params.dp_config  = null          // DeepProfiler config.json
params.run_deepprofiler = false   // toggle the deep-learning branch

workflow {
    if( !params.input_dir ) error "Set --input_dir (root of raw images, one subdir per plate)."

    // One work item per plate directory — Nextflow fans these out across the cluster.
    plates = Channel.fromPath("${params.input_dir}/*", type: 'dir')

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
