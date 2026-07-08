include { DEEPPROFILER } from './nextflow/workflows/deepprofiler.nf'
include { CELLPROFILER } from './nextflow/workflows/cellprofiler.nf'

// Entry point. The CellProfiler and DeepProfiler branches are independent feature-extraction
// workflows. `--pipeline` selects which one to run (default set in nextflow.config).
workflow {
    main:
    // Publish targets shared across both branches.
    ch_qc_reports          = channel.empty()
    ch_raw_profiles        = channel.empty()
    ch_normalized_profiles = channel.empty()
    ch_selected_profiles   = channel.empty()
    ch_consensus_profiles  = channel.empty()
    ch_report_figures      = channel.empty()

    if( params.pipeline == 'deepprofiler' ) {
        dp = DEEPPROFILER()
        ch_qc_reports          = dp.qc_reports
        ch_raw_profiles        = dp.raw_profiles
        ch_normalized_profiles = dp.normalized_profiles
        ch_consensus_profiles  = dp.consensus_profiles
        ch_report_figures      = dp.report_figures
    }
    else if( params.pipeline == 'cellprofiler' ) {
        cp = CELLPROFILER()
        ch_qc_reports          = cp.qc_reports
        ch_raw_profiles        = cp.raw_profiles
        ch_normalized_profiles = cp.normalized_profiles
        ch_selected_profiles   = cp.selected_profiles
        ch_consensus_profiles  = cp.consensus_profiles
        ch_report_figures      = cp.report_figures
    }
    else {
        error "Unknown --pipeline '${params.pipeline}'. Choose 'deepprofiler' or 'cellprofiler'."
    }

    publish:
    qc_reports          = ch_qc_reports
    raw_profiles        = ch_raw_profiles
    normalized_profiles = ch_normalized_profiles
    selected_profiles   = ch_selected_profiles
    consensus_profiles  = ch_consensus_profiles
    report_figures      = ch_report_figures
}

// Outputs land under `<pipeline>/...` so the two branches never collide in the results dir.
// selected_profiles is only produced by the CellProfiler branch.
output {
    qc_reports          { path { plate_id, _qc_dir -> "${params.pipeline}/qc/${plate_id}" } }
    raw_profiles        { path "${params.pipeline}/raw" }
    normalized_profiles { path "${params.pipeline}/normalized" }
    selected_profiles   { path "${params.pipeline}" }
    consensus_profiles  { path "${params.pipeline}" }
    report_figures      { path "${params.pipeline}" }
}
