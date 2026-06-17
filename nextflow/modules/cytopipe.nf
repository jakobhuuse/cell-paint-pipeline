process CYTOPIPE_CELLPROFILER_DEEPPROFILER {
    tag { plate_id }
    label 'cytopipe'
    publishDir { "${params.outdir}/cytopipe/${plate_id}" }, mode: 'copy', enabled: params.publish_intermediates

    input:
    tuple val(plate_id), path(deepprofiler)
    path platemap

    output:
    tuple val(plate_id),
        path('deepprofiler/locations/*', type: 'dir'),
        path('deepprofiler/metadata/index.csv'), emit: metadata

    script:
    """
    cytopipe cellprofiler-deepprofiler ${deepprofiler} deepprofiler ${platemap}
    """
}

process CYTOPIPE_CELLPROFILER_PARQUET {
    tag { plate_id }
    label 'cytopipe'
    label 'cytotable'
    publishDir { "${params.outdir}/" }, mode: 'copy'

    input:
    tuple val(plate_id), path(measurement, stageAs: 'measurement/*')

    output:
    tuple val(plate_id), path("${plate_id}.parquet"), emit: cellprofiler_parquet

    script:
    """
    cytopipe cellprofiler-parquet measurement ${plate_id}.parquet
    """
}

process CYTOPIPE_DEEPPROFILER_PARQUET {
    tag { plate_id }
    label 'cytopipe'
    label 'cytotable'
    publishDir { "${params.outdir}/" }, mode: 'copy'

    input:
    tuple val(plate_id), path(npz, stageAs: 'features/*')

    output:
    tuple val(plate_id), path("${plate_id}.parquet"), emit: deepprofiler_parquet

    script:
    """
    cytopipe deepprofiler-parquet features ${plate_id}.parquet
    """
}

