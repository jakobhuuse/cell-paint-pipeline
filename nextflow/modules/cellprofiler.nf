process CELLPROFILER {
    tag { plate_id }
    publishDir { "${params.outdir}/cellprofiler/${plate_id}" }, mode: 'copy'

    input:
    tuple val(plate_id), path(plate)
    path cppipe

    output:
    tuple val(plate_id), path('measurements'), emit: measurements

    //Make output dir, create filelist, and run cellprofiler
    script:
    """
    mkdir -p measurements

    find -L "\$(readlink -f ${plate})" -name '*.tif' ! -iname '*_thumb*' > filelist.txt

    cellprofiler -c -r \\
        -p ${cppipe} \\
        --file-list filelist.txt \\
        -o measurements
    """
}
