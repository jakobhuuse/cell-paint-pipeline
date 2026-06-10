// pycytominer stage — annotate -> normalize -> feature-select -> aggregate.
// Image: cytomining/pycytominer (has a built-in file-based CLI).

process PYCYTOMINER {
    tag "${plate}"
    publishDir "${params.outdir}/pycytominer/${plate}", mode: 'copy'

    input:
    tuple val(plate), path(single_cell)
    path platemap

    output:
    tuple val(plate), path("${plate}_profiles.parquet"), emit: profiles

    script:
    // STUB: chain the needed pycytominer ops via its CLI. Methods/ops come from conf/params.
    """
    python -m pycytominer annotate \\
        --profiles ${single_cell} \\
        --platemap ${platemap} \\
        --output ${plate}_annotated.parquet
    python -m pycytominer normalize \\
        --profiles ${plate}_annotated.parquet \\
        --output ${plate}_normalized.parquet
    python -m pycytominer feature_select \\
        --profiles ${plate}_normalized.parquet \\
        --output ${plate}_selected.parquet
    python -m pycytominer aggregate \\
        --profiles ${plate}_selected.parquet \\
        --output ${plate}_profiles.parquet
    """

    stub:
    """
    echo "pycytominer annotate|normalize|feature_select|aggregate for ${plate}" > cmd.txt
    touch ${plate}_profiles.parquet
    """
}
