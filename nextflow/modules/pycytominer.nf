nextflow.enable.types = true

// The five core functions of pycytominer as processes.
// The processes should be used from top to bottom,
// where DeepProfiler skips annotation and feature selection.

include { PlateParquet } from '../types.nf'

process PYCYTOMINER_AGGREGATE {
    tag { pp.id }
    label 'pycytominer'

    input:
    pp: PlateParquet
    features: String

    output:
    record(id: pp.id, parquet: file("${pp.id}.aggregated.parquet"))

    script:
    """
    pycytominer aggregate \\
        --profiles "${pp.parquet}" \\
        --output_file "${pp.id}.aggregated.parquet" \\
        --strata "${params.pycytominer_aggregate_strata}" \\
        --features "${features}" \\
        --output_type parquet
    """
}

process PYCYTOMINER_ANNOTATE {
    tag { pp.id }
    label 'pycytominer'

    input:
    pp: PlateParquet
    platemap: Path

    output:
    record(id: pp.id, parquet: file("${pp.id}.annotated.parquet"))

    script:
    """
    pycytominer annotate \\
        --profiles "${pp.parquet}" \\
        --output_file "${pp.id}.annotated.parquet" \\
        --platemap "${platemap}" \\
        --output_type parquet
    """
}

process PYCYTOMINER_NORMALIZE {
    tag { pp.id }
    label 'pycytominer'

    input:
    pp: PlateParquet
    features: String

    output:
    record(id: pp.id, parquet: file("${pp.id}.normalized.parquet"))

    script:
    """
    pycytominer normalize \\
        --profiles "${pp.parquet}" \\
        --output_file "${pp.id}.normalized.parquet" \\
        --samples "${params.pycytominer_normalize_samples}" \\
        --features "${features}" \\
        --output_type parquet
    """
}

process PYCYTOMINER_FEATURE_SELECT {
    label 'pycytominer'

    input:
    profiles: Path
    features: String

    output:
    record(selected: file('feature_select.parquet'))

    script:
    """
    pycytominer feature_select \\
        --profiles "${profiles}" \\
        --output_file feature_select.parquet \\
        --operation "${params.pycytominer_feature_select_ops}" \\
        --features "${features}" \\
        --output_type parquet
    """
}

process PYCYTOMINER_CONSENSUS {
    label 'pycytominer'

    input:
    profiles: Path
    features: String

    output:
    record(consensus: file('consensus.parquet'))

    script:
    """
    pycytominer consensus \\
        --profiles "${profiles}" \\
        --output_file consensus.parquet \\
        --replicate_columns "${params.pycytominer_consensus_columns}" \\
        --features "${features}" \\
        --output_type parquet
    """
}
