process CYTOPIPE_BRIDGE {
    tag { plate_id }
    label 'cytopipe'
    publishDir { "${params.outdir}/cytopipe/${plate_id}" }, mode: 'copy'

    input:
    tuple val(plate_id), path(measurement)
    path platemap

    output:
    tuple val(plate_id),
          path('bridge/locations/*', type: 'dir'),
          path('bridge/metadata/index.csv'), emit: metadata

    script:
    """
    cytopipe bridge ${measurement} bridge ${platemap}
    """
}
