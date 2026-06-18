// Sorted CellProfiler input images for a plate (thumbnails excluded).
def plateTifs(dir) {
    files("${dir}/**/*.tif").findAll { tif -> !tif.name.toLowerCase().contains('_thumb') }.sort()
}

// Per-plate input images: (plate_id, [sorted tifs]).
def plateImages() {
    channel.fromPath("${params.input_dir}/${params.plate_glob}", type: 'dir')
        .map { dir -> tuple(dir.name, plateTifs(dir)) }
}

// Platemap for the run.
def platemap() {
    file("${params.input_dir}/platemap.csv", checkIfExists: true)
}
