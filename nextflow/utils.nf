// Sorted CellProfiler input images for a plate (thumbnails excluded).
def plateTifs(dir) {
    files("${dir}/**/*.tif").findAll { tif -> !tif.name.toLowerCase().contains('_thumb') }.sort()
}

// Per-plate input images: (plate_id, [sorted tifs]).
def plateImages() {
    channel.fromPath("${params.input_dir}/${params.plate_glob}", type: 'dir')
        .map { dir -> tuple(dir.name, plateTifs(dir)) }
        .filter { _id, tifs -> tifs } 
}

// Fan a per-plate (plate_id, images) channel out into image-set chunks:
def imageChunks(ch, chunkSize) {
    ch.flatMap { plate_id, imgs ->
        int sites = imgs.size().intdiv(5)
        int sz = chunkSize as int
        (1..sites).step(sz).collect { first ->
            int last = Math.min((first + sz) - 1, sites)
            tuple(plate_id, first, last, imgs)
        }
    }
}

// As imageChunks, but carries the per-plate illum dir.
def cellprofilerChunks(ch, chunkSize) {
    imageChunks(ch.map { plate_id, _illum, imgs -> tuple(plate_id, imgs) }, chunkSize)
        .combine(ch.map { plate_id, illum, _imgs -> tuple(plate_id, illum) }, by: 0)
        .map { plate_id, first, last, imgs, illum -> tuple(plate_id, first, last, illum, imgs) }
}

// Platemap for the run.
def platemap() {
    file("${params.input_dir}/platemap.csv", checkIfExists: true)
}

// pycytominer --features list for DeepProfiler embeddings: efficientnet_1..N.
def deepprofilerFeatures() {
    (1..params.deepprofiler_embedding_dim).collect { n -> "efficientnet_${n}" }.join(',')
}
