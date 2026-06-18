include { CELLPROFILER_ILLUM; CELLPROFILER_ANALYZE } from '../modules/cellprofiler.nf'
include { plateImages; platemap } from '../modules/utils.nf'
include { CYTOPIPE_CELLPROFILER_PARQUET; CYTOPIPE_CELLPROFILER_DEEPPROFILER; CYTOPIPE_DEEPPROFILER_PARQUET } from '../modules/cytopipe.nf'
include { DEEPPROFILER_PROFILE } from '../modules/deepprofiler.nf'

workflow {
    images = plateImages()

    CELLPROFILER_ILLUM(images, file(params.illum_cppipe))

    CELLPROFILER_ANALYZE(CELLPROFILER_ILLUM.out.illum.join(images), file(params.combined_cppipe))

    CYTOPIPE_CELLPROFILER_PARQUET(CELLPROFILER_ANALYZE.out.measurement)

    CYTOPIPE_CELLPROFILER_DEEPPROFILER(
        CELLPROFILER_ANALYZE.out.image_csv.join(CELLPROFILER_ANALYZE.out.locations),
        platemap()
    )

    profile_input = CYTOPIPE_CELLPROFILER_DEEPPROFILER.out.metadata
        .join(CELLPROFILER_ANALYZE.out.images)
        .map { plate_id, locations_dir, index, imgs -> tuple(plate_id, imgs, locations_dir, index) }

    DEEPPROFILER_PROFILE(
        profile_input,
        file(params.deepprofiler_config),
        file(params.deepprofiler_model)
    )

    CYTOPIPE_DEEPPROFILER_PARQUET(DEEPPROFILER_PROFILE.out.features)
}
