// CytoTable stage — convert CellProfiler output into single-cell parquet.
// Image: our cytopipe image (ENTRYPOINT `cytopipe`).

process CYTOTABLE {
    tag "${plate}"
    publishDir "${params.outdir}/cytotable/${plate}", mode: 'copy'

    input:
    tuple val(plate), path(measurements)

    output:
    tuple val(plate), path("${plate}.parquet"), emit: single_cell

    script:
    """
    cytopipe convert \\
        --source ${measurements}/${plate}.sqlite \\
        --dest ${plate}.parquet \\
        --preset cellprofiler_sqlite
    """

    // STUB: echo the command (the Python stub raises NotImplementedError otherwise).
    stub:
    """
    echo "cytopipe convert --source ${measurements}/${plate}.sqlite --dest ${plate}.parquet" > cmd.txt
    touch ${plate}.parquet
    """
}
