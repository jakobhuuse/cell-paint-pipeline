process CELLPROFILER_ILLUM {
    tag { plate_id }
    label 'cellprofiler'
   
    input:
    tuple val(plate_id), path(images, stageAs: 'images/*')
    path cppipe

    output:
    tuple val(plate_id), path('illum'), emit: illum

    script:
    """
    mkdir -p illum
    readlink -f images/*.tif > filelist.txt

    cellprofiler -c -r \\
        -p ${cppipe} \\
        --file-list filelist.txt \\
        -o illum
    """
}

process CELLPROFILER_ANALYSIS {
    tag { "${plate_id} ${first}-${last}" }
    label 'cellprofiler'

    input:
    tuple val(plate_id), val(first), val(last), path(illum), path(images, stageAs: 'images/*')
    path cppipe

    output:
    tuple val(plate_id), path("${plate_id}.${first}-${last}.sqlite"), emit: measurement

    script:
    """
    mkdir -p out
    readlink -f images/*.tif > filelist.txt

    sed "s|file:ILLUM_PLACEHOLDER|file:\${PWD}/illum|g" ${cppipe} > run_pipeline.cppipe

    cellprofiler -c -r \\
        -p run_pipeline.cppipe \\
        --file-list filelist.txt \\
        -f ${first} -l ${last} \\
        -o out

    mv out/measurements.sqlite ${plate_id}.${first}-${last}.sqlite
    """
}

// Identifies nuclei locations from raw images.
process CELLPROFILER_NUCLEI {
    tag { "${plate_id} ${first}-${last}" }
    label 'cellprofiler'

    input:
    tuple val(plate_id), val(first), val(last), path(images, stageAs: 'images/*')
    path cppipe

    output:
    tuple val(plate_id), path('out/Image.csv'),              emit: image_csv
    tuple val(plate_id), path('out/locations/*-Nuclei.csv'), emit: locations

    script:
    """
    mkdir -p out
    readlink -f images/*.tif > filelist.txt

    cellprofiler -c -r \\
        -p ${cppipe} \\
        --file-list filelist.txt \\
        -f ${first} -l ${last} \\
        -o out
    """
}