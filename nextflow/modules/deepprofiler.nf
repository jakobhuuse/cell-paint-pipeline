process DEEPPROFILER_PROFILE {
    tag { plate_id }
    label 'deepprofiler'
    publishDir { "${params.outdir}/deepprofiler/${plate_id}" }, mode: 'copy', enabled: params.publish_intermediates

    input:
    tuple val(plate_id),
          path(images,    stageAs: 'staged/images'),
          path(locations, stageAs: 'staged/locations'),
          path(index,     stageAs: 'inputs/metadata/index.csv')
    path config, stageAs: 'inputs/config/*'
    path model,  stageAs: 'outputs/results/checkpoint/*'

    output:
    tuple val(plate_id), path('*.npz'), emit: features

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

    # DeepProfiler writes outputs/results/features/<plate>/<Well>/<Site>.npz;
    # flatten to <Well>_<Site>.npz in the publish directory to comply with cytotable documentation.

    for npz in outputs/results/features/${plate_id}/*/*.npz; do
        well=\$(basename "\$(dirname "\$npz")")
        site=\$(basename "\$npz" .npz)
        mv "\$npz" "\${well}_\${site}.npz"
    done
    """
}
