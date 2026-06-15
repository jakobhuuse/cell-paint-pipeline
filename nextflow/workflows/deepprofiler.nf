include { CELLPROFILER_ILLUM; CELLPROFILER_DEEPPROFILER } from '../modules/cellprofiler.nf'
include { CYTOPIPE_BRIDGE }      from '../modules/cytopipe.nf'
include { DEEPPROFILER_PROFILE } from '../modules/deepprofiler.nf'

workflow {
    plates = channel.fromPath("${params.input_dir}/${params.plate_glob}", type: 'dir')
        .map { dir -> tuple(dir.name, dir) }

    platemap = file("${params.input_dir}/platemap.csv", checkIfExists: true)

    CELLPROFILER_ILLUM(plates, file(params.illum_cppipe))

    CELLPROFILER_DEEPPROFILER(
        CELLPROFILER_ILLUM.out.illum.join(plates),
        file(params.deepprofiler_cppipe)
    )

    CYTOPIPE_BRIDGE(CELLPROFILER_DEEPPROFILER.out.measurement, platemap)

    profile_input = CYTOPIPE_BRIDGE.out.metadata
        .join(CELLPROFILER_DEEPPROFILER.out.images)
        .map { id, locations, index, images -> tuple(id, images, locations, index) }

    DEEPPROFILER_PROFILE(
        profile_input,
        file(params.deepprofiler_config),
        file(params.deepprofiler_model)
    )
}
