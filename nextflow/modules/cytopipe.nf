nextflow.enable.types = true

include { BridgeInput; PlateMeta; PlateMeasurements; PlateFeatures; PlateParquet } from '../types.nf'

process CYTOPIPE_BRIDGE {
    tag { b.id }
    label 'cytopipe'

    input:
    b: BridgeInput
    platemap: Path

    stage:
    stageAs b.image_csv, 'measurement/Image.csv'
    stageAs b.locations, 'measurement/locations/*'

    output:
    record(
        id: b.id,
        locations: file('deepprofiler/locations/*', type: 'dir'),
        index: file('deepprofiler/metadata/index.csv'),
    )

    script:
    """
    cytopipe bridge measurement deepprofiler ${platemap}
    """
}

process CYTOPIPE_CELLPROFILER_PARQUET {
    tag { m.id }
    label 'cytopipe'
    label 'cytotable'

    input:
    m: PlateMeasurements

    stage:
    stageAs m.measurements, 'measurement/*'

    output:
    record(id: m.id, parquet: file("${m.id}.parquet"))

    script:
    """
    cytopipe convert cellprofiler measurement ${m.id}.parquet
    """
}

process CYTOPIPE_DEEPPROFILER_PARQUET {
    tag { f.id }
    label 'cytopipe'
    label 'cytotable'

    input:
    f: PlateFeatures

    stage:
    stageAs f.npz, 'features/*'

    output:
    record(id: f.id, parquet: file("${f.id}.parquet"))

    script:
    """
    cytopipe convert deepprofiler features ${f.id}.parquet
    """
}

process CYTOPIPE_CONCAT {
    label 'cytopipe'

    input:
    parts: Bag<Path>

    stage:
    stageAs parts, 'parts/*'

    output:
    record(combined: file('combined.parquet'))

    script:
    """
    cytopipe convert concat parts combined.parquet
    """
}
