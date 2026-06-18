include { CELLPROFILER_ILLUM; CELLPROFILER_ANALYSIS } from '../modules/cellprofiler.nf'
include { plateImages } from '../modules/utils.nf'
include { CYTOPIPE_CELLPROFILER_PARQUET } from '../modules/cytopipe.nf'

workflow {
    images = plateImages()

    CELLPROFILER_ILLUM(images, file(params.illum_cppipe))

    CELLPROFILER_ANALYSIS(CELLPROFILER_ILLUM.out.illum.join(images), file(params.analysis_cppipe))

    CYTOPIPE_CELLPROFILER_PARQUET(CELLPROFILER_ANALYSIS.out.measurement)
}
