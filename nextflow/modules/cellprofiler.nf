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

    cellprofiler -c -r \\
        -p ${cppipe} \\
        --data-file ${load_data} \\
        -i "\$PWD" \\
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

    cellprofiler -c -r \\
        -p ${cppipe} \\
        --data-file ${load_data} \\
        -i "\$PWD" \\
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

    cellprofiler -c -r \\
        -p ${cppipe} \\
        --data-file ${load_data} \\
        -i "\$PWD" \\
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

    cellprofiler -c -r \\
        -p ${cppipe} \\
        --data-file ${load_data} \\
        -i "\$PWD" \\
        -o chunk${chunk_id}

    # Unique per-chunk name so the grouped tables don't collide when staged for the bridge.
    cp chunk${chunk_id}/Image.csv ${plate_id}.${chunk_id}.Image.csv
    """
}
