include { DEEPPROFILER } from './nextflow/workflows/deepprofiler.nf'
include { CELLPROFILER } from './nextflow/workflows/cellprofiler.nf'
include { QC } from './nextflow/workflows/qc.nf'

// Entry point. `--pipeline` selects which of three independent workflows to run (default set
// in nextflow.config), the CellProfiler and DeepProfiler feature-extraction branches, or the
// branch-agnostic `qc` review pass (run this first, then point --qc_exclude_file at its output
// before running either of the other two).
workflow {
    main:
    // Publish targets shared across all three pipeline choices.
    ch_qc_reports          = channel.empty()
    ch_gallery             = channel.empty()
    ch_raw_profiles        = channel.empty()
    ch_normalized_profiles = channel.empty()
    ch_selected_profiles   = channel.empty()
    ch_consensus_profiles  = channel.empty()
    ch_report_figures      = channel.empty()
    ch_skipped_chunks      = channel.empty()

    if( params.pipeline == 'deepprofiler' ) {
        dp = DEEPPROFILER()
        ch_raw_profiles        = dp.raw_profiles
        ch_normalized_profiles = dp.normalized_profiles
        ch_consensus_profiles  = dp.consensus_profiles
        ch_report_figures      = dp.report_figures
    }
    else if( params.pipeline == 'cellprofiler' ) {
        cp = CELLPROFILER()
        ch_raw_profiles        = cp.raw_profiles
        ch_normalized_profiles = cp.normalized_profiles
        ch_selected_profiles   = cp.selected_profiles
        ch_consensus_profiles  = cp.consensus_profiles
        ch_report_figures      = cp.report_figures
        ch_skipped_chunks      = cp.skipped_chunks
    }
    else if( params.pipeline == 'qc' ) {
        q = QC()
        ch_qc_reports = q.qc_reports
        ch_gallery    = q.gallery
    }
    else {
        error "Unknown --pipeline '${params.pipeline}'. Choose 'deepprofiler', 'cellprofiler', or 'qc'."
    }

    publish:
    qc_reports          = ch_qc_reports
    gallery             = ch_gallery
    raw_profiles        = ch_raw_profiles
    normalized_profiles = ch_normalized_profiles
    selected_profiles   = ch_selected_profiles
    consensus_profiles  = ch_consensus_profiles
    report_figures      = ch_report_figures
    skipped_chunks      = ch_skipped_chunks
}

// Outputs land under `<pipeline>/...` so the three choices never collide in the results dir.
output {
    qc_reports          { path { plate_id, _qc_dir -> "${params.pipeline}/${plate_id}" } }
    gallery             { path "${params.pipeline}" }
    raw_profiles        { path "${params.pipeline}/raw" }
    normalized_profiles { path "${params.pipeline}/normalized" }
    selected_profiles   { path "${params.pipeline}" }
    consensus_profiles  { path "${params.pipeline}" }
    report_figures      { path "${params.pipeline}" }
    // Per plate, one .skipped.txt per chunk that had zero segmented objects (e.g. every
    // cell in it died), so that's visible in results instead of only a build-time log line.
    skipped_chunks      { path { plate_id, _files -> "${params.pipeline}/qc/${plate_id}/skipped_chunks" } }
}
