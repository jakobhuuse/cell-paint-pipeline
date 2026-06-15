process CELLPROFILER_ILLUM {
    tag { plate_id }
    label 'cellprofiler'
    publishDir { "${params.outdir}/cellprofiler/${plate_id}" }, mode: 'copy'

    input:
    tuple val(plate_id), path(plate)
    path cppipe

    output:
    tuple val(plate_id), path('illum'), emit: illum

    script:
    """
    mkdir -p illum

    find -L "\$(readlink -f ${plate})" -name '*.tif' ! -iname '*_thumb*' > filelist.txt

    cellprofiler -c -r \\
        -p ${cppipe} \\
        --file-list filelist.txt \\
        -o illum
    """
}

process CELLPROFILER_ANALYSIS {
    tag { plate_id }
    label 'cellprofiler'
    publishDir { "${params.outdir}/cellprofiler/${plate_id}" }, mode: 'copy'

    input:
    tuple val(plate_id), path(illum), path(plate)
    path cppipe

    output:
    tuple val(plate_id), path('measurement'), emit: measurement

    script:
    """
    mkdir -p measurement

    find -L "\$(readlink -f ${plate})" -name '*.tif' ! -iname '*_thumb*' > filelist.txt

    sed "s|file:ILLUM_PLACEHOLDER|file:\${PWD}/illum|g" ${cppipe} > run_pipeline.cppipe

    cellprofiler -c -r \\
        -p run_pipeline.cppipe \\
        --file-list filelist.txt \\
        -o measurement
    """
}

process CELLPROFILER_DEEPPROFILER {
    tag { plate_id }
    label 'cellprofiler'
    publishDir { "${params.outdir}/cellprofiler/${plate_id}" }, mode: 'copy'

    input:
    tuple val(plate_id), path(illum), path(plate)
    path cppipe

    output:
    tuple val(plate_id), path('measurement'), emit: measurement
    tuple val(plate_id), path("measurement/images/"), emit: images

    script:
    """
    mkdir -p measurement

    find -L "\$(readlink -f ${plate})" -name '*.tif' ! -iname '*_thumb*' > filelist.txt

    sed "s|file:ILLUM_PLACEHOLDER|file:\${PWD}/illum|g" ${cppipe} > run_pipeline.cppipe

    cellprofiler -c -r \\
        -p run_pipeline.cppipe \\
        --file-list filelist.txt \\
        -o measurement
    """
}
