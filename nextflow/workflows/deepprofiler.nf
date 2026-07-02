include { CELLPROFILER_NUCLEI } from '../modules/cellprofiler.nf'
include { plateImages; platemap; deepprofilerFeatures; loadDataChunks } from '../utils.nf'
include { CYTOPIPE_LOADDATA; CYTOPIPE_BRIDGE; CYTOPIPE_DEEPPROFILER_PARQUET; CYTOPIPE_CONCAT; CYTOPIPE_REPORT_DEEPPROFILER } from '../modules/cytopipe.nf'
include { DEEPPROFILER_PREPARE; DEEPPROFILE } from '../modules/deepprofiler.nf'
include { PYCYTOMINER_AGGREGATE; PYCYTOMINER_NORMALIZE; PYCYTOMINER_CONSENSUS } from '../modules/pycytominer.nf'

workflow {
    main:
    images = plateImages()

    loaddata = CYTOPIPE_LOADDATA(images, false)

    chunks = loadDataChunks(loaddata.csv, images, params.cellprofiler_chunk_size)

    cellprofiler = CELLPROFILER_NUCLEI(chunks, file(params.nuclei_cppipe))
    
    image_csv = cellprofiler.image_csv.groupTuple()

    locations = cellprofiler.locations
        .groupTuple()
        .map { plate_id, nested -> tuple(plate_id, nested.flatten()) }

    bridge = CYTOPIPE_BRIDGE(
        image_csv.join(locations),
        platemap()
    )

    prepared = DEEPPROFILER_PREPARE(
        images.join(bridge.metadata).map { plate_id, imgs, _locations_dir, index -> tuple(plate_id, imgs, index) },
        file(params.deepprofiler_config)
    )

    profile_input = prepared.compressed
        .join(bridge.metadata)
        .map { plate_id, compressed, locations_dir, index -> tuple(plate_id, compressed, locations_dir, index) }

    profiled = DEEPPROFILE(
        profile_input,
        file(params.deepprofiler_config),
        file(params.deepprofiler_model)
    )

    single_cell = CYTOPIPE_DEEPPROFILER_PARQUET(profiled.features)

    //Pycytominer
    features = deepprofilerFeatures()

    aggregated = PYCYTOMINER_AGGREGATE(single_cell.deepprofiler_parquet, features, params.pycytominer_aggregate_strata_dp)
    normalized = PYCYTOMINER_NORMALIZE(aggregated.aggregated, features)
    cohort = CYTOPIPE_CONCAT(normalized.normalized.map { _plate_id, profiles -> profiles }.collect())
    consensus = PYCYTOMINER_CONSENSUS(cohort.combined, features)

    report = CYTOPIPE_REPORT_DEEPPROFILER(
        normalized.normalized.map { _plate_id, profiles -> profiles }.collect(),
        single_cell.deepprofiler_parquet.map { _plate_id, sc -> sc }.collect(),
        consensus.consensus
    )

    publish:
    raw_profiles = single_cell.deepprofiler_parquet
    normalized_profiles = normalized.normalized
    consensus_profiles  = consensus.consensus
    report_figures      = report.report
}

output {
    raw_profiles { path 'deepprofiler/raw' }
    normalized_profiles { path 'deepprofiler/normalized' }
    consensus_profiles  { path 'deepprofiler' }
    report_figures      { path 'deepprofiler' }
}
