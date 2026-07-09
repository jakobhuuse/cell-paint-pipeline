// The five core pycytominer functions as processes, used top to bottom.
// DeepProfiler skips annotation and feature selection.

process PYCYTOMINER_AGGREGATE {
    tag { plate_id }
    label 'pycytominer'

    input:
    tuple val(plate_id), path(profiles)
    val features
    val strata

    output:
    tuple val(plate_id), path("${plate_id}.aggregated.parquet"), emit: aggregated

    script:
    """
    pycytominer aggregate \\
        --profiles "${profiles}" \\
        --output_file "${plate_id}.aggregated.parquet" \\
        --strata "${strata}" \\
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
    # Normalize the platemap the same way cytopipe's bridge does.
    python3 -c "import pandas as pd; df = pd.read_csv('${platemap}', skipinitialspace=True, dtype=str, encoding='utf-8-sig'); df.columns = df.columns.str.strip(); df = df.apply(lambda c: c.str.strip()); df.to_csv('platemap.clean.csv', index=False)"

    pycytominer annotate \\
        --profiles "${profiles}" \\
        --output_file "${plate_id}.annotated.parquet" \\
        --platemap "platemap.clean.csv" \\
        --join_on '${params.pycytominer_annotate_join_on}' \\
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
    label 'cohort'

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
    label 'cohort'

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
