nextflow.enable.types = true

include { Plate; ImageChunk; IllumChunk } from '../types.nf'

process CELLPROFILER_ILLUM {
    tag { plate.id }
    label 'cellprofiler'

    input:
    plate: Plate
    cppipe: Path

    stage:
    stageAs plate.images, 'images/*'

    output:
    record(id: plate.id, illum: file('illum', type: 'dir'))

    script:
    """
    mkdir -p illum
    readlink -f images/*.tif > filelist.txt

    cellprofiler -c -r \\
        -p ${cppipe} \\
        --file-list filelist.txt \\
        -o illum
    """
}

process CELLPROFILER_ANALYSIS {
    tag { "${chunk.id} ${chunk.first}-${chunk.last}" }
    label 'cellprofiler'

    input:
    chunk: IllumChunk
    cppipe: Path

    stage:
    stageAs chunk.illum, 'illum'
    stageAs chunk.images, 'images/*'

    output:
    record(id: chunk.id, measurement: file("${chunk.id}.${chunk.first}-${chunk.last}.sqlite"))

    script:
    """
    mkdir -p out
    readlink -f images/*.tif > filelist.txt

    sed "s|file:ILLUM_PLACEHOLDER|file:\${PWD}/illum|g" ${cppipe} > run_pipeline.cppipe

    cellprofiler -c -r \\
        -p run_pipeline.cppipe \\
        --file-list filelist.txt \\
        -f ${chunk.first} -l ${chunk.last} \\
        -o out

    mv out/measurements.sqlite ${chunk.id}.${chunk.first}-${chunk.last}.sqlite
    """
}

// Segmentation only: identifies nuclei locations from raw images. Illumination
// correction is handled downstream by DeepProfiler's prepare step.
process CELLPROFILER_DEEPPROFILER {
    tag { "${chunk.id} ${chunk.first}-${chunk.last}" }
    label 'cellprofiler'

    input:
    chunk: ImageChunk
    cppipe: Path

    stage:
    stageAs chunk.images, 'images/*'

    output:
    image_csv = record(id: chunk.id, image_csv: file('out/Image.csv'))
    locations = record(id: chunk.id, locations: files('out/locations/*-Nuclei.csv'))

    script:
    """
    mkdir -p out
    readlink -f images/*.tif > filelist.txt

    cellprofiler -c -r \\
        -p ${cppipe} \\
        --file-list filelist.txt \\
        -f ${chunk.first} -l ${chunk.last} \\
        -o out
    """
}
