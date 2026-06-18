// Plate input images for CellProfiler's --file-list (thumbnails excluded).
def tifFind(plate) {
    "find -L \"\$(readlink -f ${plate})\" -name '*.tif' ! -iname '*_thumb*'"
}

process CELLPROFILER_ILLUM {
    tag { plate_id }
    label 'cellprofiler'
    publishDir { "${params.outdir}/cellprofiler/${plate_id}" }, mode: 'copy', enabled: params.publish_intermediates

    input:
    tuple val(plate_id), path(plate)
    path cppipe

    output:
    tuple val(plate_id), path('illum'), emit: illum

    script:
    """
    mkdir -p illum

    ${tifFind(plate)} > filelist.txt

    cellprofiler -c -r \\
        -p ${cppipe} \\
        --file-list filelist.txt \\
        -o illum
    """
}

process CELLPROFILER_CHUNKS {
    tag { plate_id }
    label 'cellprofiler'

    input:
    tuple val(plate_id), path(plate)

    output:
    tuple val(plate_id), path('chunks.csv'), emit: chunks

    script:
    """
    n=\$(${tifFind(plate)} | wc -l)
    sets=\$(( (n + 4) / 5 ))
    awk -v sets=\$sets -v step=${params.cp_chunk_size} 'BEGIN {
        for (f = 1; f <= sets; f += step) {
            l = f + step - 1; if (l > sets) l = sets
            print f "," l
        }
    }' > chunks.csv
    """
}

process CELLPROFILER_ANALYSIS {
    tag { "${plate_id}:${first}-${last}" }
    label 'cellprofiler'
    publishDir { "${params.outdir}/cellprofiler/${plate_id}" }, mode: 'copy', enabled: params.publish_intermediates

    input:
    tuple val(plate_id), path(illum), path(plate), val(first), val(last)
    path cppipe

    output:
    tuple val(plate_id), path("${plate_id}_${first}-${last}.sqlite"), emit: measurement

    script:
    """
    mkdir -p out

    # sort -> deterministic image-set numbering, so -f/-l line up with the chunk ranges
    ${tifFind(plate)} | sort > filelist.txt

    sed "s|file:ILLUM_PLACEHOLDER|file:\${PWD}/illum|g" ${cppipe} > run_pipeline.cppipe

    cellprofiler -c -r \\
        -p run_pipeline.cppipe \\
        --file-list filelist.txt \\
        -f ${first} -l ${last} \\
        -o out

    mv out/measurements.sqlite ${plate_id}_${first}-${last}.sqlite
    """
}

process CELLPROFILER_DEEPPROFILER {
    tag { "${plate_id}:${first}-${last}" }
    label 'cellprofiler'
    publishDir { "${params.outdir}/cellprofiler/${plate_id}" }, mode: 'copy', enabled: params.publish_intermediates

    input:
    tuple val(plate_id), path(illum), path(plate), val(first), val(last)
    path cppipe

    output:
    tuple val(plate_id), path('deepprofiler/Image.csv'),             emit: image_csv
    tuple val(plate_id), path('deepprofiler/locations/*-Nuclei.csv'), emit: locations
    tuple val(plate_id), path('deepprofiler/images/*'),              emit: images

    script:
    """
    mkdir -p deepprofiler

    # sort -> deterministic image-set numbering, so -f/-l line up with the chunk ranges
    ${tifFind(plate)} | sort > filelist.txt

    sed "s|file:ILLUM_PLACEHOLDER|file:\${PWD}/illum|g" ${cppipe} > run_pipeline.cppipe

    cellprofiler -c -r \\
        -p run_pipeline.cppipe \\
        --file-list filelist.txt \\
        -f ${first} -l ${last} \\
        -o deepprofiler
    """
}

// Split each plate into cp_chunk_size-site ranges and fan out per-chunk CellProfiler tasks.
// Shared by the analysis and DeepProfiler workflows.
workflow CP_CHUNK_TASKS {
    take:
        plates   // (plate_id, plate_dir)
        illum    // (plate_id, illum_dir)

    main:
        CELLPROFILER_CHUNKS(plates)

        chunks = CELLPROFILER_CHUNKS.out.chunks
            .splitCsv(elem: 1)
            .map { plate_id, row -> tuple(plate_id, row[0] as int, row[1] as int) }

    emit:
        // (plate_id, illum, plate, first, last) - one CellProfiler task per chunk
        illum.join(plates).combine(chunks, by: 0)
}
