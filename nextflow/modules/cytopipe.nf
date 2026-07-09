process CYTOPIPE_LOADDATA {
    tag { with_illum ? "${plate_id} +illum" : plate_id }
    label 'cytopipe'

    input:
    tuple val(plate_id), path(images, stageAs: 'images/*')
    val with_illum
    val chunk_size

    output:
    tuple val(plate_id), path("${plate_id}.load_data.csv"),                            emit: csv
    tuple val(plate_id), path('chunks/*.load_data.csv'), path('chunks/*.images.txt'),  emit: chunks

    script:
    def illum_flag = with_illum ? '--with-illum' : ''
    """
    cytopipe loaddata images ${plate_id}.load_data.csv \\
        --plate ${plate_id} --chunk-size ${chunk_size} ${illum_flag}
    """
}

process CYTOPIPE_BRIDGE {
    tag { plate_id }
    label 'cytopipe'
    
    input:
    tuple val(plate_id),
          path(image_csvs, stageAs: 'measurement/image_csv/*'),
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
    // Optional: a plate whose CellProfiler compartments are all empty (no
    // segmented objects) yields no single cells, so cytopipe writes no parquet
    // and the plate drops out of the cohort instead of aborting the run.
    tuple val(plate_id), path("${plate_id}.parquet"), emit: cellprofiler_parquet, optional: true

    script:
    """
    cytopipe convert cellprofiler measurement ${plate_id}.parquet --threads ${task.cpus}
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
    cytopipe convert deepprofiler features ${plate_id}.parquet --threads ${task.cpus}
    """
}

process CYTOPIPE_CONCAT {
    label 'cytopipe'
    label 'cohort'

    input:
    path 'parts/*'

    output:
    path 'combined.parquet', emit: combined

    script:
    """
    cytopipe convert concat parts combined.parquet --threads ${task.cpus}
    """
}

process CYTOPIPE_REPORT_DEEPPROFILER {
    label 'cytopipe'
    label 'cohort'

    input:
    path(normalized, stageAs: 'deepprofiler/normalized/*')
    path(raw, stageAs: 'deepprofiler/raw/*')
    path(consensus, stageAs: 'deepprofiler/consensus.parquet')

    output:
    path 'report', emit: report

    script:
    """
    cytopipe report deepprofiler --engine deepprofiler -o report
    """
}

process CYTOPIPE_REPORT_CELLPROFILER {
    label 'cytopipe'
    label 'cohort'

    input:
    path(normalized, stageAs: 'cellprofiler/normalized/*')
    path(selected, stageAs: 'cellprofiler/selected/feature_select.parquet')
    path(raw, stageAs: 'cellprofiler/raw/*')
    path(consensus, stageAs: 'cellprofiler/consensus.parquet')

    output:
    path 'report', emit: report

    script:
    """
    cytopipe report cellprofiler --engine cellprofiler -o report
    """
}

