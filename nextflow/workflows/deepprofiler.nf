include { CELLPROFILER_NUCLEI } from '../modules/cellprofiler.nf'
include { plateImages; platemap; deepprofilerFeatures; loadDataChunks; flag } from '../utils.nf'
include { CYTOPIPE_LOADDATA; CYTOPIPE_LOADDATA_FILTER; CYTOPIPE_BRIDGE; CYTOPIPE_DEEPPROFILER_PARQUET; CYTOPIPE_AGGREGATE; CYTOPIPE_CONCAT; CYTOPIPE_REPORT_DEEPPROFILER } from '../modules/cytopipe.nf'
include { DEEPPROFILER_PREPARE; DEEPPROFILE } from '../modules/deepprofiler.nf'
include { PYCYTOMINER_NORMALIZE; PYCYTOMINER_CONSENSUS } from '../modules/pycytominer.nf'

workflow DEEPPROFILER {
    main:
    images = plateImages()

    loaddata_raw = CYTOPIPE_LOADDATA(images, false, params.cellprofiler_chunk_size)

    // Filtered before nuclei segmentation (a no-op against the empty conf/qc/no_exclusions.csv
    // default). Unlike the CellProfiler branch, QC and nuclei segmentation are the same
    // CELLPROFILER_NUCLEI pass here, so there is no cheaper way to exclude images that skips it.
    loaddata = CYTOPIPE_LOADDATA_FILTER(
        loaddata_raw.csv,
        file(params.qc_exclude_file),
        params.cellprofiler_chunk_size
    )

    chunks = loadDataChunks(loaddata.chunks, images)

    // nuclei.cppipe only segments nuclei and exports their locations plus flat image metadata,
    // it does not compute or publish QC measurements. QC review lives entirely in `--pipeline qc`
    // (nextflow/workflows/qc.nf), which uses 1_QC.cppipe instead.
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

    // Profiling (aggregation, normalization, cohort consensus, report). Gated by
    // params.profiling so tiny fixtures can stop at single-cell parquet.
    normalized_profiles = channel.empty()
    consensus_profiles  = channel.empty()
    report_figures      = channel.empty()

    if( flag(params.profiling) ) {
        features = deepprofilerFeatures()

        aggregated = CYTOPIPE_AGGREGATE(single_cell.deepprofiler_parquet, features, params.pycytominer_aggregate_strata_dp)
        normalized = PYCYTOMINER_NORMALIZE(aggregated.aggregated, features)
        cohort = CYTOPIPE_CONCAT(normalized.normalized.map { _plate_id, profiles -> profiles }.collect())
        consensus = PYCYTOMINER_CONSENSUS(cohort.combined, features)

        report = CYTOPIPE_REPORT_DEEPPROFILER(
            normalized.normalized.map { _plate_id, profiles -> profiles }.collect(),
            single_cell.deepprofiler_parquet.map { _plate_id, sc -> sc }.collect(),
            consensus.consensus
        )

        normalized_profiles = normalized.normalized
        consensus_profiles  = consensus.consensus
        report_figures      = report.report
    }

    emit:
    raw_profiles        = single_cell.deepprofiler_parquet
    normalized_profiles = normalized_profiles
    consensus_profiles  = consensus_profiles
    report_figures      = report_figures
}
