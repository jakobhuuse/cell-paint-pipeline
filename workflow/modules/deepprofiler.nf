// DeepProfiler stage (optional deep-learning branch) — extract single-cell embeddings.
// Image: our custom deepprofiler image (GPU/TensorFlow).

process DEEPPROFILER {
    tag "${plate}"
    label 'gpu'
    publishDir "${params.outdir}/deepprofiler/${plate}", mode: 'copy'

    input:
    tuple val(plate), path(dp_metadata)
    path dp_config

    output:
    tuple val(plate), path('features'), emit: embeddings

    script:
    // STUB: real invocation needs --root with config/checkpoint + index.csv from `bridge`.
    """
    mkdir -p features
    python -m deepprofiler --root . --config ${dp_config} --metadata ${dp_metadata} profile
    """

    stub:
    """
    mkdir -p features
    echo "deepprofiler profile for ${plate}" > features/cmd.txt
    """
}
