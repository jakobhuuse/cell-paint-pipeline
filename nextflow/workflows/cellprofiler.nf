include { CELLPROFILER_ILLUM; CELLPROFILER_ANALYSIS } from '../modules/cellprofiler.nf'

workflow {
    plates = channel.fromPath("${params.input_dir}/${params.plate_glob}", type: 'dir')
        .map { dir -> tuple(dir.name, dir) }

    CELLPROFILER_ILLUM(plates, file(params.illum_cppipe))

    CELLPROFILER_ANALYSIS(
        CELLPROFILER_ILLUM.out.illum.join(plates),
        file(params.analysis_cppipe)
    )
}
