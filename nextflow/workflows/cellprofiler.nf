nextflow.enable.types = true

include { CELLPROFILER_ILLUM; CELLPROFILER_ANALYSIS } from '../modules/cellprofiler.nf'
include { plateImages; cellprofilerChunks } from '../utils.nf'
include { CYTOPIPE_CELLPROFILER_PARQUET } from '../modules/cytopipe.nf'

// Types only; values come from nextflow.config (or --param overrides).
params {
    input_dir: String
    plate_glob: String
    illum_cppipe: String
    cellprofiler_chunk_size: Integer
    analysis_cppipe: String
}

workflow {
    main:
    images = plateImages()

    illum = CELLPROFILER_ILLUM(images, file(params.illum_cppipe))

    chunks = cellprofilerChunks(illum.join(images, by: 'id'), params.cellprofiler_chunk_size)

    analysis = CELLPROFILER_ANALYSIS(chunks, file(params.analysis_cppipe))

    // Regroup per-chunk sqlites per plate (groupTuple has no field `by`).
    measurement = analysis
        .map { r -> tuple(r.id, r.measurement) }
        .groupTuple(by: 0)
        .map { id, nested -> record(id: id, measurements: nested) }

    single_cell = CYTOPIPE_CELLPROFILER_PARQUET(measurement)

    publish:
    raw_profiles = single_cell.map { r -> r.parquet }
}

output {
    raw_profiles { path 'cellprofiler/raw' }
}
