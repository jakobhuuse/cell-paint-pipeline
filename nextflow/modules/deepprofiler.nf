process DEEPPROFILER_PROFILE {
    tag { plate_id }
    label 'deepprofiler'
    publishDir { "${params.outdir}/deepprofiler/${plate_id}" }, mode: 'copy'

    input:
    tuple val(plate_id),
          path(images,    stageAs: 'staged/images'),
          path(locations, stageAs: 'staged/locations'),
          path(index,     stageAs: 'inputs/metadata/index.csv')
    path config, stageAs: 'inputs/config/*'
    path model,  stageAs: 'outputs/results/checkpoint/*'

    output:
    tuple val(plate_id), path('features'), emit: features

    script:
    """
    mkdir -p inputs/images inputs/locations
    mv staged/images    inputs/images/${plate_id}
    mv staged/locations inputs/locations/${plate_id}

    mkdir -p outputs/results/features

    python3 -m deepprofiler \\
        --root="\${PWD}" \\
        --config=${file(params.deepprofiler_config).name} \\
        profile

    mv outputs/results/features/${plate_id} features
    """
}
