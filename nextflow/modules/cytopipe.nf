// Build a CellProfiler LoadData CSV from a plate's raw channel images. PathName columns are
// emitted as the __IMAGES__/__ILLUM__ placeholders, which the CellProfiler processes sed to the
// staged dirs at run time. with_illum adds Illum<channel> columns for the analysis pipeline.
process CYTOPIPE_LOADDATA {
    tag { with_illum ? "${plate_id} +illum" : plate_id }
    label 'cytopipe'

    input:
    tuple val(plate_id), path(images, stageAs: 'images/*')
    val with_illum

    output:
    tuple val(plate_id), path("${plate_id}.load_data.csv"), emit: csv

    script:
    def illum_flag = with_illum ? '--with-illum' : ''
    """
    cytopipe loaddata images ${plate_id}.load_data.csv --plate ${plate_id} ${illum_flag}
    """
}

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

