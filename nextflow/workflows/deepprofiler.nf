include { CELLPROFILER_ILLUM; CELLPROFILER_DEEPPROFILER } from '../modules/cellprofiler.nf'
include { plateImages; platemap; deepprofilerFeatures; cellprofilerChunks } from '../utils.nf'
include { CYTOPIPE_BRIDGE; CYTOPIPE_DEEPPROFILER_PARQUET; CYTOPIPE_CONCAT } from '../modules/cytopipe.nf'
include { DEEPPROFILE } from '../modules/deepprofiler.nf'
include { PYCYTOMINER_AGGREGATE; PYCYTOMINER_NORMALIZE; PYCYTOMINER_CONSENSUS } from '../modules/pycytominer.nf'

workflow {
    main:
    images = plateImages()

    illum = CELLPROFILER_ILLUM(images, file(params.illum_cppipe))

    chunks = cellprofilerChunks(illum.illum.join(images), params.cellprofiler_chunk_size)

    cellprofiler = CELLPROFILER_DEEPPROFILER(chunks, file(params.deepprofiler_cppipe))

    //Regroup data from different chunks
    image_csv = cellprofiler.image_csv
        .collectFile(keepHeader: true, skip: 1) { plate_id, csv -> ["${plate_id}.Image.csv", csv] }
        .map { f -> tuple(f.name.replaceFirst(/\.Image\.csv$/, ''), f) }

    locations = cellprofiler.locations
        .groupTuple()
        .map { plate_id, nested -> tuple(plate_id, nested.flatten()) }

    corrected_images = cellprofiler.images
        .groupTuple()
        .map { plate_id, nested -> tuple(plate_id, nested.flatten()) }

    bridge = CYTOPIPE_BRIDGE(
        image_csv.join(locations),
        platemap()
    )

    profile_input = bridge.metadata
        .join(corrected_images)
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
    raw_profiles = single_cell.deepprofiler_parquet
    normalized_profiles = normalized.normalized
    consensus_profiles  = consensus.consensus
}

output {
    raw_profiles { path 'deepprofiler/raw' }
    normalized_profiles { path 'deepprofiler/normalized' }
    consensus_profiles  { path 'deepprofiler' }
}
