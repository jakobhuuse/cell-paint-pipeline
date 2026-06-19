include { CELLPROFILER_ILLUM; CELLPROFILER_DEEPPROFILER } from '../modules/cellprofiler.nf'
include { plateImages; platemap; deepprofilerFeatures } from '../modules/utils.nf'
include { CYTOPIPE_BRIDGE; CYTOPIPE_DEEPPROFILER_PARQUET; CYTOPIPE_CONCAT } from '../modules/cytopipe.nf'
include { DEEPPROFILE } from '../modules/deepprofiler.nf'
include { PYCYTOMINER_AGGREGATE; PYCYTOMINER_NORMALIZE; PYCYTOMINER_CONSENSUS } from '../modules/pycytominer.nf'

workflow {
    main:
    images = plateImages()

    illum = CELLPROFILER_ILLUM(images, file(params.illum_cppipe))

    cellprofiler = CELLPROFILER_DEEPPROFILER(illum.illum.join(images), file(params.deepprofiler_cppipe))

    bridge = CYTOPIPE_BRIDGE(
        cellprofiler.image_csv.join(cellprofiler.locations),
        platemap()
    )

    profile_input = bridge.metadata
        .join(cellprofiler.images)
        .map { plate_id, locations_dir, index, imgs -> tuple(plate_id, imgs, locations_dir, index) }

    profiled = DEEPPROFILE(
        profile_input,
        file(params.deepprofiler_config),
        file(params.deepprofiler_model)
    )

    single_cell = CYTOPIPE_DEEPPROFILER_PARQUET(profiled.features)

    features = deepprofilerFeatures()

    aggregated = PYCYTOMINER_AGGREGATE(single_cell.deepprofiler_parquet, features)
    normalized = PYCYTOMINER_NORMALIZE(aggregated.aggregated, features)

    cohort = CYTOPIPE_CONCAT(normalized.normalized.map { _plate_id, profiles -> profiles }.collect())

    consensus = PYCYTOMINER_CONSENSUS(cohort.combined, features)

    publish:
    normalized_profiles = normalized.normalized
    consensus_profiles  = consensus.consensus
}

output {
    normalized_profiles { path 'deepprofiler' ; mode 'copy' }
    consensus_profiles  { path 'deepprofiler' ; mode 'copy' }
}
