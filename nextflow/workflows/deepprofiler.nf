include { CELLPROFILER_ILLUM; CELLPROFILER_DEEPPROFILER } from '../modules/cellprofiler.nf'
include { plateImages; platemap } from '../modules/utils.nf'
include { CYTOPIPE_BRIDGE; CYTOPIPE_DEEPPROFILER_PARQUET } from '../modules/cytopipe.nf'
include { DEEPPROFILE } from '../modules/deepprofiler.nf'

workflow {
    images = plateImages()

    CELLPROFILER_ILLUM(images, file(params.illum_cppipe))

    CELLPROFILER_DEEPPROFILER(CELLPROFILER_ILLUM.out.illum.join(images), file(params.deepprofiler_cppipe))

    CYTOPIPE_BRIDGE(
        CELLPROFILER_DEEPPROFILER.out.image_csv.join(CELLPROFILER_DEEPPROFILER.out.locations),
        platemap()
    )

    profile_input = CYTOPIPE_BRIDGE.out.metadata
        .join(CELLPROFILER_DEEPPROFILER.out.images)
        .map { plate_id, locations_dir, index, imgs -> tuple(plate_id, imgs, locations_dir, index) }

    DEEPPROFILE(
        profile_input,
        file(params.deepprofiler_config),
        file(params.deepprofiler_model)
    )

    CYTOPIPE_DEEPPROFILER_PARQUET(DEEPPROFILE.out.features)
}
