include { CELLPROFILER_ILLUM; CP_CHUNK_TASKS; CELLPROFILER_ANALYSIS } from '../modules/cellprofiler.nf'
include { CYTOPIPE_CELLPROFILER_PARQUET } from '../modules/cytopipe.nf'

workflow {
    plates = channel.fromPath("${params.input_dir}/${params.plate_glob}", type: 'dir')
        .map { dir -> tuple(dir.name, dir) }

    CELLPROFILER_ILLUM(plates, file(params.illum_cppipe))

    CP_CHUNK_TASKS(plates, CELLPROFILER_ILLUM.out.illum)

    CELLPROFILER_ANALYSIS(CP_CHUNK_TASKS.out, file(params.analysis_cppipe))

    // regroup per-chunk sqlite by plate
    measurements = CELLPROFILER_ANALYSIS.out.measurement.groupTuple()

    CYTOPIPE_CELLPROFILER_PARQUET(measurements)
}
