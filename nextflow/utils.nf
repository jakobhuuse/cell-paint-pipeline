nextflow.enable.types = true

include { Plate; ImageChunk; IllumChunk } from './types.nf'

// Helpers build typed records as channel payloads. Channel-level type annotations
// on these functions are omitted: a dataflow channel cannot be cast to the typed
// `Channel<T>` at runtime (static typing is still a preview feature).

// Sorted CellProfiler input images for a plate (thumbnails excluded).
def plateTifs(dir) {
    files("${dir}/**/*.tif").toSorted().findAll { tif -> !tif.name.toLowerCase().contains('_thumb') }
}

// Per-plate input images -> Plate records.
def plateImages() {
    channel.fromPath("${params.input_dir}/${params.plate_glob}", type: 'dir')
        .map { dir -> record(id: dir.name, images: plateTifs(dir)) }
        .filter { p -> p.images.size() > 0 }
}

// Fan a per-plate Plate channel out into ImageChunk records (5 channels per site).
def imageChunks(ch, chunkSize) {
    ch.flatMap { plate ->
        int sites = plate.images.size().intdiv(5)
        int nChunks = (sites + chunkSize - 1).intdiv(chunkSize)
        (0 ..< nChunks).collect { k ->
            int first = (k * chunkSize) + 1
            int last = Math.min((first + chunkSize) - 1, sites)
            record(id: plate.id, first: first, last: last, images: plate.images)
        }
    }
}

// As imageChunks, but carries the per-plate illum dir as IllumChunk records.
// `combine` has no field-name `by`, so a transient (id, ...) tuple re-attaches it.
def cellprofilerChunks(ch, chunkSize) {
    def chunks = imageChunks(ch.map { r -> record(id: r.id, images: r.images) }, chunkSize)
    def illum  = ch.map { r -> tuple(r.id, r.illum) }
    chunks
        .map { c -> tuple(c.id, c) }
        .combine(illum, by: 0)
        .map { id, chunk, illumDir ->
            record(id: id, first: chunk.first, last: chunk.last, illum: illumDir, images: chunk.images)
        }
}

// Platemap for the run.
def platemap() {
    file("${params.input_dir}/platemap.csv", checkIfExists: true)
}

// pycytominer --features list for DeepProfiler embeddings: efficientnet_1..N.
def deepprofilerFeatures() {
    int dim = params.deepprofiler_embedding_dim as Integer
    (1..dim).collect { n -> "efficientnet_${n}" }.join(',')
}
