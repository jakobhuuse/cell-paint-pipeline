process CYTOPIPE_CELLPROFILER_DEEPPROFILER {
    tag { plate_id }
    label 'cytopipe'
    publishDir { "${params.outdir}/cytopipe/${plate_id}" }, mode: 'copy', enabled: params.publish_intermediates

    input:
    tuple val(plate_id),
          path('measurement/Image.csv'),
          path(locations, stageAs: 'measurement/locations/*')
    path platemap

    output:
    tuple val(plate_id),
        path('deepprofiler/locations/*', type: 'dir'),
        path('deepprofiler/metadata/index.csv'), emit: metadata

    script:
    """
    cytopipe bridge measurement deepprofiler ${platemap}
    """
}

process CYTOPIPE_CELLPROFILER_PARQUET {
    tag { plate_id }
    label 'cytopipe'
    label 'cytotable'
    publishDir { "${params.outdir}/cellprofiler/" }, mode: 'copy'

    input:
    tuple val(plate_id), path(measurement, stageAs: 'measurement/*')

    output:
    tuple val(plate_id), path("${plate_id}.parquet"), emit: cellprofiler_parquet

    script:
    """
    cytopipe convert cellprofiler measurement ${plate_id}.parquet
    """
}

process CYTOPIPE_DEEPPROFILER_PARQUET {
    tag { plate_id }
    label 'cytopipe'
    label 'cytotable'
    publishDir { "${params.outdir}/deepprofiler/" }, mode: 'copy'

    input:
    tuple val(plate_id), path(npz, stageAs: 'features/*')

    output:
    tuple val(plate_id), path("${plate_id}.parquet"), emit: deepprofiler_parquet

    script:
    """
    cytopipe convert deepprofiler features ${plate_id}.parquet
    """
}

