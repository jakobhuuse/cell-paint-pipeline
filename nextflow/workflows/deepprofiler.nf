nextflow.enable.types = true

include { CELLPROFILER_DEEPPROFILER } from '../modules/cellprofiler.nf'
include { plateImages; platemap; deepprofilerFeatures; imageChunks } from '../utils.nf'
include { CYTOPIPE_BRIDGE; CYTOPIPE_DEEPPROFILER_PARQUET; CYTOPIPE_CONCAT } from '../modules/cytopipe.nf'
include { DEEPPROFILER_PREPARE; DEEPPROFILE } from '../modules/deepprofiler.nf'
include { PYCYTOMINER_AGGREGATE; PYCYTOMINER_NORMALIZE; PYCYTOMINER_CONSENSUS } from '../modules/pycytominer.nf'

// Types only; values come from nextflow.config (or --param overrides).
params {
    input_dir: String
    plate_glob: String
    cellprofiler_chunk_size: Integer
    deepprofiler_cppipe: String
    deepprofiler_config: String
    deepprofiler_model: String
    deepprofiler_embedding_dim: Integer
    pycytominer_aggregate_strata: String
    pycytominer_normalize_samples: String
    pycytominer_consensus_columns: String
}

workflow {
    main:
    images = plateImages()

    // CellProfiler segments nuclei only; DeepProfiler's prepare does illum correction.
    chunks = imageChunks(images, params.cellprofiler_chunk_size)

    cellprofiler = CELLPROFILER_DEEPPROFILER(chunks, file(params.deepprofiler_cppipe))

    // Regroup chunk outputs per plate. collectFile emits a plain file, re-wrapped to a record.
    image_csv = cellprofiler.image_csv
        .collectFile(keepHeader: true, skip: 1) { r -> ["${r.id}.Image.csv", r.image_csv] }
        .map { f ->
            Path csv = file(f)
            record(id: csv.name.replaceFirst(/\.Image\.csv$/, ''), image_csv: csv)
        }

    // groupTuple has no field `by`, so key by id with a transient tuple.
    locations = cellprofiler.locations
        .map { r -> tuple(r.id, r.locations) }
        .groupTuple(by: 0)
        .map { id, nested -> record(id: id, locations: nested.flatten()) }

    bridge = CYTOPIPE_BRIDGE(image_csv.join(locations, by: 'id'), platemap())

    // Illumination correction + compression on the raw images, keyed by the index.
    prepared = DEEPPROFILER_PREPARE(
        images.join(bridge, by: 'id').map { r -> record(id: r.id, images: r.images, index: r.index) },
        file(params.deepprofiler_config),
    )

    profiled = DEEPPROFILE(
        prepared.join(bridge, by: 'id').map { r ->
            record(id: r.id, compressed: r.compressed, locations: r.locations, index: r.index)
        },
        file(params.deepprofiler_config),
        file(params.deepprofiler_model),
    )

    single_cell = CYTOPIPE_DEEPPROFILER_PARQUET(profiled)

    features = deepprofilerFeatures()

    aggregated = PYCYTOMINER_AGGREGATE(single_cell, features)
    normalized = PYCYTOMINER_NORMALIZE(aggregated, features)

    cohort = CYTOPIPE_CONCAT(normalized.map { r -> r.parquet }.collect())

    consensus = PYCYTOMINER_CONSENSUS(cohort.map { r -> r.combined }, features)

    publish:
    raw_profiles = single_cell.map { r -> r.parquet }
    normalized_profiles = normalized.map { r -> r.parquet }
    consensus_profiles = consensus.map { r -> r.consensus }
}

output {
    raw_profiles { path 'deepprofiler/raw' }
    normalized_profiles { path 'deepprofiler/normalized' }
    consensus_profiles  { path 'deepprofiler' }
}
