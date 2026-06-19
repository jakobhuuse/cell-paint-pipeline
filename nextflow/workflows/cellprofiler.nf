include { CELLPROFILER_ILLUM; CELLPROFILER_ANALYSIS } from '../modules/cellprofiler.nf'
include { plateImages } from '../modules/utils.nf'
include { CYTOPIPE_CELLPROFILER_PARQUET } from '../modules/cytopipe.nf'

workflow {
    main:
    images = plateImages()

    illum = CELLPROFILER_ILLUM(images, file(params.illum_cppipe))

    analysis = CELLPROFILER_ANALYSIS(illum.illum.join(images), file(params.analysis_cppipe))

    single_cell = CYTOPIPE_CELLPROFILER_PARQUET(analysis.measurement)

    publish:
    cellprofiler_parquet = single_cell.cellprofiler_parquet
}

output {
    cellprofiler_parquet { path 'cellprofiler' ; mode 'copy' }
}
