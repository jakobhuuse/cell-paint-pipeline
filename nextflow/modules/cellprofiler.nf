// CellProfiler runs are driven by a LoadData CSV (--data-file). Each process substitutes the
// __IMAGES__ and __ILLUM__ PathName placeholders with the staged dirs before running.

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
    tag { "${plate_id} chunk ${chunk_idx}" }
    label 'cellprofiler'

    input:
    tuple val(plate_id), val(chunk_idx), path(load_data), path(images, stageAs: 'images/*'), path(illum)
    path cppipe

    output:
    tuple val(plate_id), path("${plate_id}.${chunk_idx}.sqlite"), emit: measurement

    script:
    """
    mkdir -p out
    sed "s|__IMAGES__|\${PWD}/images|g; s|__ILLUM__|\${PWD}/${illum}|g" ${load_data} > load_data.csv

    cellprofiler -c -r \\
        -p ${cppipe} \\
        --data-file load_data.csv \\
        -o out

    mv out/measurements.sqlite ${plate_id}.${chunk_idx}.sqlite
    """
}

// Identifies nuclei locations from raw images (feeds DeepProfiler).
process CELLPROFILER_NUCLEI {
    tag { "${plate_id} chunk ${chunk_idx}" }
    label 'cellprofiler'

    input:
    tuple val(plate_id), val(chunk_idx), path(load_data), path(images, stageAs: 'images/*')
    path cppipe

    output:
    tuple val(plate_id), path('out/Image.csv'),              emit: image_csv
    tuple val(plate_id), path('out/locations/*-Nuclei.csv'), emit: locations

    script:
    """
    mkdir -p out
    sed "s|__IMAGES__|\${PWD}/images|g" ${load_data} > load_data.csv

    cellprofiler -c -r \\
        -p ${cppipe} \\
        --data-file load_data.csv \\
        -o out
    """
}
