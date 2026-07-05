process CELLPROFILER_QC {
    tag { "${plate_id} chunk ${chunk_id}" }
    label 'cellprofiler'

    input:
    tuple val(plate_id), val(chunk_id), path(load_data), path(images, stageAs: 'images/*')
    path cppipe

    output:
    tuple val(plate_id), path("chunk${chunk_id}"), emit: qc

    script:
    """
    mkdir -p chunk${chunk_id}
    sed "s|__IMAGES__|\${PWD}/images|g" ${load_data} > load_data.csv

    cellprofiler -c -r \\
        -p ${cppipe} \\
        --data-file load_data.csv \\
        -o chunk${chunk_id}
    """
}

process CELLPROFILER_ILLUM {
    tag { plate_id }
    label 'cellprofiler'

    input:
    tuple val(plate_id), path(load_data), path(images, stageAs: 'images/*')
    path cppipe

    output:
    tuple val(plate_id), path('illum'), emit: illum

    script:
    """
    mkdir -p illum
    sed "s|__IMAGES__|\${PWD}/images|g" ${load_data} > load_data.csv

    cellprofiler -c -r \\
        -p ${cppipe} \\
        --data-file load_data.csv \\
        -o illum
    """
}

process CELLPROFILER_ANALYSIS {
    tag { "${plate_id} chunk ${chunk_id}" }
    label 'cellprofiler'

    input:
    tuple val(plate_id), val(chunk_id), path(load_data), path(images, stageAs: 'images/*'), path(illum)
    path cppipe

    output:
    tuple val(plate_id), path("${plate_id}.${chunk_id}.sqlite"), emit: measurement

    script:
    """
    mkdir -p out
    sed "s|__IMAGES__|\${PWD}/images|g; s|__ILLUM__|\${PWD}/${illum}|g" ${load_data} > load_data.csv

    cellprofiler -c -r \\
        -p ${cppipe} \\
        --data-file load_data.csv \\
        -o out

    mv out/measurements.sqlite ${plate_id}.${chunk_id}.sqlite
    """
}

process CELLPROFILER_NUCLEI {
    tag { "${plate_id} chunk ${chunk_id}" }
    label 'cellprofiler'

    input:
    tuple val(plate_id), val(chunk_id), path(load_data), path(images, stageAs: 'images/*')
    path cppipe

    output:
    tuple val(plate_id), path("${plate_id}.${chunk_id}.Image.csv"),          emit: image_csv
    tuple val(plate_id), path("chunk${chunk_id}/locations/*-Nuclei.csv"),    emit: locations
    tuple val(plate_id), path("chunk${chunk_id}"),                          emit: qc

    script:
    """
    mkdir -p chunk${chunk_id}
    sed "s|__IMAGES__|\${PWD}/images|g" ${load_data} > load_data.csv

    cellprofiler -c -r \\
        -p ${cppipe} \\
        --data-file load_data.csv \\
        -o chunk${chunk_id}

    # Unique per-chunk name so the grouped tables don't collide when staged for the bridge.
    cp chunk${chunk_id}/Image.csv ${plate_id}.${chunk_id}.Image.csv
    """
}
