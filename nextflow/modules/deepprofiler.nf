process DEEPPROFILE {
    tag { plate_id }
    label 'deepprofiler'

    input:
    tuple val(plate_id),
          path(compressed, stageAs: 'staged/compressed'),
          path(locations,  stageAs: 'staged/locations'),
          path(index,      stageAs: 'inputs/metadata/index.csv')
    path config, stageAs: 'inputs/config/*'
    path model,  stageAs: 'outputs/results/checkpoint/*'

    output:
    tuple val(plate_id), path('*.npz'), emit: features

    script:
    """
    mkdir -p outputs/compressed/images inputs/locations
    mv staged/compressed outputs/compressed/images/${plate_id}
    mv staged/locations  inputs/locations/${plate_id}

    mkdir -p outputs/results/features

    python3 -m deepprofiler \\
        --root="\${PWD}" \\
        --config=${file(params.deepprofiler_config).name} \\
        profile

    # Flatten DeepProfiler's <plate>/<Well>/<Site>.npz to <Well>_<Site>.npz for cytotable.
    for npz in outputs/results/features/${plate_id}/*/*.npz; do
        well=\$(basename "\$(dirname "\$npz")")
        site=\$(basename "\$npz" .npz)
        mv "\$npz" "\${well}_\${site}.npz"
    done
    """
}

process DEEPPROFILER_PREPARE {
    tag { plate_id }
    label 'deepprofiler_cpu'

    input:
    tuple val(plate_id),
          path(images, stageAs: 'staged/images/*'),
          path(index,  stageAs: 'inputs/metadata/index.csv')
    path config, stageAs: 'inputs/config/*'

    output:
    tuple val(plate_id), path("outputs/compressed/images/${plate_id}"), emit: compressed

    script:
    """
    mkdir -p inputs/images/${plate_id}
    for tif in staged/images/*.tif; do
        ln -s "\$(readlink -f "\$tif")" "inputs/images/${plate_id}/\$(basename "\${tif%.tif}").tiff"
    done

    python3 -m deepprofiler \\
        --root="\${PWD}" \\
        --config=${file(params.deepprofiler_config).name} \\
        prepare
    """
}
