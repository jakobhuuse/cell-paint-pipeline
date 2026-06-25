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

// The image files a chunk's LoadData rows reference (every Image_FileName_Orig* cell), mapped back
// to the staged File objects so the CellProfiler task stages only the images it needs.
def imagesForChunk(csvFile, allImages) {
    def lines = csvFile.readLines()
    def header = lines[0].split(',')
    def origCols = (0..<header.size()).findAll { id -> header[id].startsWith('Image_FileName_Orig') }
    def byName = allImages.collectEntries { img -> [(img.name): img] }
    lines.tail()
        .collectMany { line -> def cells = line.split(','); origCols.collect { colId -> cells[colId] } }
        .unique()
        .collect { name -> byName[name] }
        .findAll()
}

// Slice a per-plate LoadData CSV into chunks of `chunkSize` image-sets.
def loadDataChunks(csvCh, imagesCh, chunkSize) {
    csvCh
        .flatMap { plate_id, csv ->
            def lines = csv.readLines()
            def header = lines[0]
            lines.tail().collate(chunkSize as int).withIndex().collect { rows, i ->
                ["${plate_id}.chunk${i + 1}.load_data.csv", ([header] + rows).join('\n') + '\n']
            }
        }
        .collectFile { name, content -> [name, content] }
        .map { f ->
            def m = (f.name =~ /^(.+)\.chunk(\d+)\.load_data\.csv$/)[0]
            tuple(m[1], m[2] as int, f)
        }
        .combine(imagesCh, by: 0)
        .map { plate_id, idx, csv, imgs -> tuple(plate_id, idx, csv, imagesForChunk(csv, imgs)) }
}

// Platemap for the run.
def platemap() {
    file("${params.input_dir}/platemap.csv", checkIfExists: true)
}

// pycytominer --features list for DeepProfiler embeddings: efficientnet_1..N.
def deepprofilerFeatures() {
    (1..params.deepprofiler_embedding_dim).collect { n -> "efficientnet_${n}" }.join(',')
}
