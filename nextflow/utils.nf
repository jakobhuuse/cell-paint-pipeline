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

// Chunk number parsed from a "chunk<N>.<...>" filename.
def chunkIndex(name) {
    (name =~ /^chunk(\d+)\./)[0][1] as int
}

// One item per chunk, carrying the staged image subset that chunk needs. The subset is read from
// cytopipe's .images.txt manifest, so the driver never parses the CSV.
def loadDataChunks(chunksCh, imagesCh) {
    chunksCh
        .flatMap { plate_id, csvs, manifests ->
            def csvList = csvs instanceof List ? csvs : [csvs]
            def manByIdx = (manifests instanceof List ? manifests : [manifests])
                .collectEntries { man -> [(chunkIndex(man.name)): man] }
            csvList.collect { csv ->
                def idx = chunkIndex(csv.name)
                tuple(plate_id, idx, csv, manByIdx[idx])
            }
        }
        .combine(imagesCh, by: 0)
        .map { plate_id, idx, csv, manifest, imgs ->
            def byName = imgs.collectEntries { img -> [(img.name): img] }
            def subset = manifest.readLines().findAll { line -> line }.collect { name -> byName[name] }.findAll()
            tuple(plate_id, idx, csv, subset)
        }
}

// Platemap for the run.
def platemap() {
    file("${params.input_dir}/platemap.csv", checkIfExists: true)
}

// pycytominer --features list for DeepProfiler embeddings: efficientnet_1..N.
def deepprofilerFeatures() {
    (1..params.deepprofiler_embedding_dim).collect { n -> "efficientnet_${n}" }.join(',')
}
