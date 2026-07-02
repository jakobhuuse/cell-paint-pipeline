include { CELLPROFILER_QC; CELLPROFILER_ILLUM; CELLPROFILER_ANALYSIS } from '../modules/cellprofiler.nf'
include { plateImages; loadDataChunks; platemap } from '../utils.nf'
include { CYTOPIPE_LOADDATA as CYTOPIPE_LOADDATA_BASE; CYTOPIPE_LOADDATA as CYTOPIPE_LOADDATA_ILLUM; CYTOPIPE_CELLPROFILER_PARQUET; CYTOPIPE_CONCAT; CYTOPIPE_REPORT_CELLPROFILER } from '../modules/cytopipe.nf'
include { PYCYTOMINER_AGGREGATE; PYCYTOMINER_ANNOTATE; PYCYTOMINER_NORMALIZE; PYCYTOMINER_FEATURE_SELECT; PYCYTOMINER_CONSENSUS } from '../modules/pycytominer.nf'

workflow {
    main:
    images = plateImages()

    // Diagnostic QC on the raw images
    qc = CELLPROFILER_QC(images, file(params.qc_cppipe))

    // Illumination is calculated across the whole plate from a base (no-illum) LoadData CSV.
    base_csv = CYTOPIPE_LOADDATA_BASE(images, false)
    illum = CELLPROFILER_ILLUM(
        images.join(base_csv.csv).map { plate_id, imgs, csv -> tuple(plate_id, csv, imgs) },
        file(params.illum_cppipe)
    )

    // Analysis runs per chunk on a with-illum CSV; thread the per-plate illum dir into each chunk.
    analysis_csv = CYTOPIPE_LOADDATA_ILLUM(images, true)
    chunks = loadDataChunks(analysis_csv.csv, images, params.cellprofiler_chunk_size)
        .combine(illum.illum, by: 0)

    analysis = CELLPROFILER_ANALYSIS(chunks, file(params.analysis_cppipe))

    // Regroup per-chunk sqlites per plate.
    measurement = analysis.measurement.groupTuple()

    single_cell = CYTOPIPE_CELLPROFILER_PARQUET(measurement)

    // Pycytominer
    features = 'infer'
    aggregated = PYCYTOMINER_AGGREGATE(single_cell.cellprofiler_parquet, features, params.pycytominer_aggregate_strata_cp)
    annotated  = PYCYTOMINER_ANNOTATE(aggregated.aggregated, platemap())
    normalized = PYCYTOMINER_NORMALIZE(annotated.annotated, features)
    cohort = CYTOPIPE_CONCAT(normalized.normalized.map { _plate_id, profiles -> profiles }.collect())
    selected  = PYCYTOMINER_FEATURE_SELECT(cohort.combined, features)
    consensus = PYCYTOMINER_CONSENSUS(selected.selected, features)

    report = CYTOPIPE_REPORT_CELLPROFILER(
        normalized.normalized.map { _plate_id, profiles -> profiles }.collect(),
        selected.selected,
        single_cell.cellprofiler_parquet.map { _plate_id, sc -> sc }.collect(),
        consensus.consensus
    )

    publish:
    qc_reports          = qc.qc
    raw_profiles        = single_cell.cellprofiler_parquet
    normalized_profiles = normalized.normalized
    selected_profiles   = selected.selected
    consensus_profiles  = consensus.consensus
    report_figures      = report.report
}

output {
    qc_reports          { path 'cellprofiler/qc' }
    raw_profiles        { path 'cellprofiler/raw' }
    normalized_profiles { path 'cellprofiler/normalized' }
    selected_profiles   { path 'cellprofiler' }
    consensus_profiles  { path 'cellprofiler' }
    report_figures      { path 'cellprofiler' }
}
