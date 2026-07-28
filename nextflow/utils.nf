def flag(value) {
    value.toString().toBoolean()
}

// Sorted CellProfiler input images for a plate (thumbnails excluded).
def plateTifs(dir) {
    files("${dir}/**/*.tif").findAll { tif -> !tif.name.toLowerCase().contains('_thumb') }.sort()
}

// platemap.csv always sits at the experiment root, whether that's params.input_dir itself, its
// parent, or its grandparent. Which of those it's found at also tells us how many levels below
// the root input_dir sits, 0 if input_dir IS the root, 1 if it's a date folder, 2 if it's a
// single plate folder, since the layout is fixed as experiment/date/plate/timepoint(optional)/
// tifs. That count drives plateDirs() below, rather than guessing from where the tifs sit: an
// optional per-plate timepoint folder makes tif depth alone ambiguous between "this dir is a
// plate with a timepoint subfolder" and "this dir is a date folder whose plates skip it".
def experimentRoot() {
    def dir = file(params.input_dir)
    def candidates = [dir, dir.parent, dir.parent?.parent]
    def index = candidates.findIndexOf { candidate -> candidate?.resolve('platemap.csv')?.exists() }
    if( index == -1 ) {
        error('No platemap.csv found near --input_dir ' + params.input_dir +
              ' (looked in: ' + candidates.findAll().join(', ') + ')')
    }
    [candidates[index], 2 - index]
}

// Resolve `params.input_dir` to plate folders regardless of which level it points at: the
// experiment root (dates/plates), a single date folder (plates), or a single plate folder itself.
def plateDirs() {
    def descents = experimentRoot()[1]
    def dirs = [file(params.input_dir)]
    descents.times {
        dirs = dirs.collectMany { dir -> dir.listFiles().findAll { child -> child.isDirectory() } }
    }
    dirs.sort { a, b -> a.name <=> b.name }
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

// Platemap for the run, resolved via experimentRoot() above.
def platemap() {
    experimentRoot()[0].resolve('platemap.csv')
}

// pycytominer --features list for DeepProfiler embeddings: efficientnet_1..N.
def deepprofilerFeatures() {
    (1..params.deepprofiler_embedding_dim).collect { n -> "efficientnet_${n}" }.join(',')
}
