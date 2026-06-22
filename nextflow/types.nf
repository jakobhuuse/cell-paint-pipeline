nextflow.enable.types = true

// Shared record types for the pipeline's channels. Records replace the positional
// tuples (`tuple val(id), path(...)`) so channel payloads are named and typed.
// `join(other, by: 'id')` merges two records by id; `groupTuple`/`combine` do not
// accept a field name, so those use a transient `(id, ...)` tuple in the workflows.

// Per-plate raw input images.
record Plate {
    id: String
    images: Bag<Path>
}

// One CellProfiler image-set chunk (sites [first, last]) of a plate's images.
record ImageChunk {
    id: String
    first: Integer
    last: Integer
    images: Bag<Path>
}

// As ImageChunk, plus the plate's illum-correction dir (for CellProfiler analysis).
record IllumChunk {
    id: String
    first: Integer
    last: Integer
    illum: Path
    images: Bag<Path>
}

// CELLPROFILER_ILLUM output: per-plate illum-correction dir.
record PlateIllum {
    id: String
    illum: Path
}

// CELLPROFILER_DEEPPROFILER segmentation outputs.
record PlateImageCsv {
    id: String
    image_csv: Path
}

record PlateLocations {
    id: String
    locations: Bag<Path>
}

// CYTOPIPE_BRIDGE input (PlateImageCsv joined with PlateLocations by id).
record BridgeInput {
    id: String
    image_csv: Path
    locations: Bag<Path>
}

// CYTOPIPE_BRIDGE output: DeepProfiler metadata handoff (locations dir + index.csv).
record PlateMeta {
    id: String
    locations: Path
    index: Path
}

// DEEPPROFILER_PREPARE input: raw images + the DeepProfiler index.
record PrepareInput {
    id: String
    images: Bag<Path>
    index: Path
}

// DEEPPROFILER_PREPARE output: illum-corrected / compressed images dir.
record PlateCompressed {
    id: String
    compressed: Path
}

// DEEPPROFILE input: compressed images + locations dir + index.
record ProfileInput {
    id: String
    compressed: Path
    locations: Path
    index: Path
}

// DEEPPROFILE output: single-cell embeddings (.npz per site).
record PlateFeatures {
    id: String
    npz: Bag<Path>
}

// CELLPROFILER_ANALYSIS output: one measurement sqlite per chunk.
record PlateMeasurement {
    id: String
    measurement: Path
}

// Grouped per-plate measurement sqlites (across chunks).
record PlateMeasurements {
    id: String
    measurements: Bag<Path>
}

// Per-plate parquet (cytopipe convert output + pycytominer per-plate steps).
record PlateParquet {
    id: String
    parquet: Path
}
