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

// Platemap for the run.
def platemap() {
    file("${params.input_dir}/platemap.csv", checkIfExists: true)
}

// pycytominer --features list for DeepProfiler embeddings: efficientnet_1..N.
def deepprofilerFeatures() {
    (1..params.deepprofiler_embedding_dim).collect { n -> "efficientnet_${n}" }.join(',')
}
