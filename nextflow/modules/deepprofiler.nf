nextflow.enable.types = true

include { PrepareInput; ProfileInput } from '../types.nf'

process DEEPPROFILE {
    tag { prof.id }
    label 'deepprofiler'

    input:
    prof: ProfileInput
    config: Path
    model: Path

    stage:
    stageAs prof.compressed, 'staged/compressed'
    stageAs prof.locations, 'staged/locations'
    stageAs prof.index, 'inputs/metadata/index.csv'
    stageAs config, 'inputs/config/*'
    stageAs model, 'outputs/results/checkpoint/*'

    output:
    record(id: prof.id, npz: files('*.npz'))

    script:
    """
    # config has compression.implement=true, so profile reads outputs/compressed/images.
    mkdir -p outputs/compressed/images inputs/locations
    mv staged/compressed outputs/compressed/images/${prof.id}
    mv staged/locations  inputs/locations/${prof.id}

    mkdir -p outputs/results/features

    python3 -m deepprofiler \\
        --root="\${PWD}" \\
        --config=${file(params.deepprofiler_config).name} \\
        profile

    # Flatten DeepProfiler's <plate>/<Well>/<Site>.npz to <Well>_<Site>.npz for cytotable.
    for npz in outputs/results/features/${prof.id}/*/*.npz; do
        well=\$(basename "\$(dirname "\$npz")")
        site=\$(basename "\$npz" .npz)
        mv "\$npz" "\${well}_\${site}.npz"
    done
    """
}

// DeepProfiler illumination correction + compression (CPU-only). Reads raw
// images, writes 8-bit illum-corrected PNGs that DEEPPROFILE then profiles.
process DEEPPROFILER_PREPARE {
    tag { prep.id }
    label 'deepprofiler_cpu'

    input:
    prep: PrepareInput
    config: Path

    stage:
    stageAs prep.images, 'staged/images/*'
    stageAs prep.index, 'inputs/metadata/index.csv'
    stageAs config, 'inputs/config/*'

    output:
    record(id: prep.id, compressed: file("outputs/compressed/images/${prep.id}", type: 'dir'))

    script:
    """
    # The index references <plate>/<stem>.tiff but raw files are .tif, so stage
    # them under inputs/images with the .tiff name DeepProfiler expects.
    mkdir -p inputs/images/${prep.id}
    for tif in staged/images/*.tif; do
        ln -s "\$(readlink -f "\$tif")" "inputs/images/${prep.id}/\$(basename "\${tif%.tif}").tiff"
    done

    python3 -m deepprofiler \\
        --root="\${PWD}" \\
        --config=${file(params.deepprofiler_config).name} \\
        prepare
    """
}
