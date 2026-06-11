include { CELLPROFILER_ILLUM; CELLPROFILER_DEEPPROFILER } from '../modules/cellprofiler.nf'

workflow {
    plates = channel.fromPath("${params.input_dir}/${params.plate_glob}", type: 'dir')
        .map { dir -> tuple(dir.name, dir) }

    CELLPROFILER_ILLUM(plates, file(params.illum_cppipe))

    CELLPROFILER_DEEPPROFILER(
        CELLPROFILER_ILLUM.out.illum.join(plates),
        file(params.deepprofiler_cppipe)
    )
}
