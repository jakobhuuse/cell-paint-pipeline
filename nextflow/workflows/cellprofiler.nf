include { CELLPROFILER_ILLUM; CELLPROFILER_ANALYSIS } from '../modules/cellprofiler.nf'
include { plateImages; cellprofilerChunks } from '../utils.nf'
include { CYTOPIPE_CELLPROFILER_PARQUET } from '../modules/cytopipe.nf'

workflow {
    main:
    images = plateImages()

    illum = CELLPROFILER_ILLUM(images, file(params.illum_cppipe))

    chunks = cellprofilerChunks(illum.illum.join(images), params.cellprofiler_chunk_size)

    analysis = CELLPROFILER_ANALYSIS(chunks, file(params.analysis_cppipe))

    // Regroup per-chunk sqlites per plate.
    measurement = analysis.measurement.groupTuple()

    single_cell = CYTOPIPE_CELLPROFILER_PARQUET(measurement)

    publish:
    raw_profiles = single_cell.cellprofiler_parquet
}

output {
    raw_profiles { path 'cellprofiler/raw' }
}
