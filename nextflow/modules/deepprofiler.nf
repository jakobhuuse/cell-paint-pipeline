process DEEPPROFILER_PROFILE {
    tag { plate_id }
    label 'deepprofiler'
    publishDir { "${params.outdir}/deepprofiler/${plate_id}" }, mode: 'copy'

    input:
    tuple val(plate_id),
          path(images,    stageAs: 'inputs/images/*'),
          path(locations, stageAs: 'inputs/locations/*'),
          path(index,     stageAs: 'inputs/metadata/index.csv')
    path config, stageAs: 'inputs/config/*'
    path model,  stageAs: 'outputs/results/checkpoint/*'

    output:
    tuple val(plate_id), path('outputs/results/features'),   emit: features
    tuple val(plate_id), path('outputs/results/logs'),       emit: logs
    tuple val(plate_id), path('outputs/results/summaries'),  emit: summaries

    script:
    """
    mkdir -p outputs/results/features outputs/results/logs outputs/results/summaries

    python3 -m deepprofiler \\
        --root="\${PWD}" \\
        --config=${file(params.deepprofiler_config).name} \\
        profile
    """
}
