process CYTOPIPE_BRIDGE {
    tag { plate_id }
    label 'cytopipe'
    
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

    input:
    tuple val(plate_id), path(npz, stageAs: 'features/*')

    output:
    tuple val(plate_id), path("${plate_id}.parquet"), emit: deepprofiler_parquet

    script:
    """
    cytopipe convert deepprofiler features ${plate_id}.parquet
    """
}

process CYTOPIPE_CONCAT {
    label 'cytopipe'

    input:
    path 'parts/*'

    output:
    path 'combined.parquet', emit: combined

    script:
    """
    cytopipe convert concat parts combined.parquet
    """
}

