def flag(value) {
    value.toString().toBoolean()
}

// Sorted CellProfiler input images for a plate (thumbnails excluded).
def plateTifs(dir) {
    files("${dir}/**/*.tif").findAll { tif -> !tif.name.toLowerCase().contains('_thumb') }.sort()
}

// True if `dir` has at least one usable .tif anywhere inside it, i.e. it's a plate folder.
def looksLikePlate(dir) {
    plateTifs(dir) as boolean
}

// Resolve `params.input_dir` to plate folders regardless of which level it points at. 
// It could be an experiment folder (dates/plates/tifs), a single date folder (plates/tifs), or a single plate
// folder (tifs directly). At each level, only children that look like the next level down are
// descended into, so stray folders (a previous run's results dir, etc.) are skipped rather than
// misread as dates or plates.
def plateDirs() {
    def root = file(params.input_dir)
    if( looksLikePlate(root) ) {
        return [root]
    }
    def children = root.listFiles().findAll { child -> child.isDirectory() }
    def plates = children.findAll { child -> looksLikePlate(child) }
    if( plates ) {
        return plates.sort { a, b -> a.name <=> b.name }
    }
    children
        .collectMany { dateDir -> dateDir.listFiles().findAll { child -> child.isDirectory() } }
        .findAll { plate -> looksLikePlate(plate) }
        .sort { a, b -> a.name <=> b.name }
}

// Per-plate input images: (plate_id, [sorted tifs]).
def plateImages() {
    channel.fromList(plateDirs())
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

// Platemap for the run. Sits at the experiment root, alongside the date folders, so it's found
// by walking up from params.input_dir whether that points at the experiment root, a date folder,
// or a single plate folder.
def platemap() {
    def dir = file(params.input_dir)
    def candidates = [dir, dir.parent, dir.parent?.parent].findAll()
    candidates.collect { candidate -> candidate.resolve('platemap.csv') }.find { file -> file.exists() } ?:
        error('No platemap.csv found near --input_dir ' + params.input_dir +
              ' (looked in: ' + candidates.join(', ') + ')')
}

// pycytominer --features list for DeepProfiler embeddings: efficientnet_1..N.
def deepprofilerFeatures() {
    (1..params.deepprofiler_embedding_dim).collect { n -> "efficientnet_${n}" }.join(',')
}
