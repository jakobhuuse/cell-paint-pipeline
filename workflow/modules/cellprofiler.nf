// CellProfiler stage — runs a .cppipe headless over one plate's images.
// Image: cellprofiler/cellprofiler (ENTRYPOINT `cellprofiler`).

process CELLPROFILER {
    tag "${plate.name}"
    publishDir "${params.outdir}/cellprofiler/${plate.name}", mode: 'copy'

    input:
    path plate
    path cppipe

    output:
    tuple val(plate.name), path('measurements'), emit: measurements
    tuple val(plate.name), path('dp_metadata'),  emit: dp_metadata

    script:
    """
    mkdir -p measurements dp_metadata
    cellprofiler -c -r -p ${cppipe} -i ${plate} -o measurements
    """

    // STUB: echo the command instead of running it (use `nextflow run ... -stub-run`).
    stub:
    """
    mkdir -p measurements dp_metadata
    echo "cellprofiler -c -r -p ${cppipe} -i ${plate} -o measurements" > measurements/cmd.txt
    touch measurements/${plate.name}.sqlite
    """
}
