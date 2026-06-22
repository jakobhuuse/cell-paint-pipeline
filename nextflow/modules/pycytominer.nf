// The five core functions of pycytominer as processes. 
// The processes should be used from top to bottom,
// where DeepProfiler skips annotation and feature selection.

process PYCYTOMINER_AGGREGATE {
    tag { plate_id }
    label 'pycytominer'

    input:
    tuple val(plate_id), path(profiles)
    val features

    output:
    tuple val(plate_id), path("${plate_id}.aggregated.parquet"), emit: aggregated

    script:
    """
    pycytominer aggregate \\
        --profiles "${profiles}" \\
        --output_file "${plate_id}.aggregated.parquet" \\
        --strata "${params.pycytominer_aggregate_strata}" \\
        --features "${features}" \\
        --output_type parquet
    """
}

process PYCYTOMINER_ANNOTATE {
    tag { plate_id }
    label 'pycytominer'

    input:
    tuple val(plate_id), path(profiles)
    path platemap

    output:
    tuple val(plate_id), path("${plate_id}.annotated.parquet"), emit: annotated

    script:
    """
    pycytominer annotate \\
        --profiles "${profiles}" \\
        --output_file "${plate_id}.annotated.parquet" \\
        --platemap "${platemap}" \\
        --output_type parquet
    """
}

process PYCYTOMINER_NORMALIZE {
    tag { plate_id }
    label 'pycytominer'

    input:
    tuple val(plate_id), path(profiles)
    val features

    output:
    tuple val(plate_id), path("${plate_id}.normalized.parquet"), emit: normalized

    script:
    """
    pycytominer normalize \\
        --profiles "${profiles}" \\
        --output_file "${plate_id}.normalized.parquet" \\
        --samples "${params.pycytominer_normalize_samples}" \\
        --features "${features}" \\
        --output_type parquet
    """
}

process PYCYTOMINER_FEATURE_SELECT {
    label 'pycytominer'

    input:
    path profiles
    val features

    output:
    path 'feature_select.parquet', emit: selected

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
    path profiles
    val features

    output:
    path 'consensus.parquet', emit: consensus

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
