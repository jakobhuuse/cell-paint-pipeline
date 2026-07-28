include { CELLPROFILER_ILLUM; CELLPROFILER_ANALYSIS } from '../modules/cellprofiler.nf'
include { plateImages; loadDataChunks; platemap; flag } from '../utils.nf'
include { CYTOPIPE_LOADDATA as CYTOPIPE_LOADDATA_BASE; CYTOPIPE_LOADDATA as CYTOPIPE_LOADDATA_ILLUM; CYTOPIPE_LOADDATA_FILTER; CYTOPIPE_CELLPROFILER_PARQUET; CYTOPIPE_CELLPROFILER_CONCAT; CYTOPIPE_AGGREGATE; CYTOPIPE_CONCAT; CYTOPIPE_REPORT_CELLPROFILER } from '../modules/cytopipe.nf'
include { PYCYTOMINER_ANNOTATE; PYCYTOMINER_NORMALIZE; PYCYTOMINER_FEATURE_SELECT; PYCYTOMINER_CONSENSUS } from '../modules/pycytominer.nf'

workflow CELLPROFILER {
    main:
    images = plateImages()

    // Base (no-illum) LoadData CSV + chunks. QC review now lives entirely in `--pipeline qc`
    // (nextflow/workflows/qc.nf), this branch no longer runs its own diagnostic QC pass.
    base_csv = CYTOPIPE_LOADDATA_BASE(images, false, params.cellprofiler_chunk_size)

    // Illum is computed over the whole plate, so it takes the un-chunked CSV. Also unfiltered,
    // a handful of excluded images doesn't meaningfully skew a whole-plate illumination function.
    illum = CELLPROFILER_ILLUM(
        images.join(base_csv.csv).map { plate_id, imgs, csv -> tuple(plate_id, csv, imgs) },
        file(params.illum_cppipe)
    )

    // Analysis runs per chunk on a with-illum CSV, filtered by qc_exclude_file (a no-op against
    // the empty conf/qc/no_exclusions.csv default). Since QC/illum above never depend on this
    // file, changing it and re-running with -resume only recomputes analysis and downstream.
    analysis_csv_raw = CYTOPIPE_LOADDATA_ILLUM(images, true, params.cellprofiler_chunk_size)
    analysis_csv = CYTOPIPE_LOADDATA_FILTER(
        analysis_csv_raw.csv,
        file(params.qc_exclude_file),
        params.cellprofiler_chunk_size
    )
    chunks = loadDataChunks(analysis_csv.chunks, images)
        .combine(illum.illum, by: 0)

    analysis = CELLPROFILER_ANALYSIS(chunks, file(params.analysis_cppipe))

    // Convert each chunk's sqlite to its own parquet part right after analysis, so peak
    // memory is bounded by one chunk instead of scaling with the whole plate.
    chunk_parquet = CYTOPIPE_CELLPROFILER_PARQUET(analysis.measurement)

    // Merge the chunk parts back into one parquet per plate.
    single_cell = CYTOPIPE_CELLPROFILER_CONCAT(chunk_parquet.cellprofiler_parquet.groupTuple())

    // Chunks skipped as empty (zero segmented objects), grouped per plate so the reason a
    // plate's single-cell parquet has fewer rows than expected is published, not just logged.
    skipped_chunks = chunk_parquet.skipped.groupTuple()

    // Profiling (aggregation, normalization, cohort feature selection/consensus, report).
    // Gated by params.profiling so tiny fixtures can stop at single-cell parquet.
    normalized_profiles = channel.empty()
    selected_profiles   = channel.empty()
    consensus_profiles  = channel.empty()
    report_figures      = channel.empty()

    if( flag(params.profiling) ) {
        features = 'infer'
        aggregated = CYTOPIPE_AGGREGATE(single_cell.cellprofiler_parquet, features, params.pycytominer_aggregate_strata_cp)
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

        normalized_profiles = normalized.normalized
        selected_profiles   = selected.selected
        consensus_profiles  = consensus.consensus
        report_figures      = report.report
    }

    emit:
    raw_profiles        = single_cell.cellprofiler_parquet
    normalized_profiles = normalized_profiles
    selected_profiles   = selected_profiles
    consensus_profiles  = consensus_profiles
    report_figures      = report_figures
    skipped_chunks      = skipped_chunks
}
