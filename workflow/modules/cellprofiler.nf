// CellProfiler stage — runs a .cppipe headless over one plate's images.
//
// One plate = one directory (e.g. <date>/<plateID>) that contains one or more
// TimePoint_* subfolders of raw .tif images. We build a CellProfiler file list of only
// the full-resolution images — the *_thumb* downsampled previews are dropped here so the
// .cppipe never sees them — and feed it via `--file-list`. Using a file list (instead of
// `-i <dir>`) keeps each image's full TimePoint_* path, so the timepoint stays recoverable
// in the Metadata module even though it is not encoded in the filename.
//
// Image: cellprofiler/cellprofiler (ENTRYPOINT `cellprofiler`).

process CELLPROFILER {
    tag { plate_id }
    publishDir { "${params.outdir}/cellprofiler/${plate_id}" }, mode: 'copy'

    input:
    tuple val(plate_id), path(plate)
    path cppipe

    output:
    tuple val(plate_id), path('measurements'), emit: measurements
    tuple val(plate_id), path('dp_metadata'),  emit: dp_metadata

    script:
    """
    mkdir -p measurements dp_metadata

    # Full-resolution images only — exclude the *_thumb* previews (filter in Nextflow).
    find -L ${plate} -type f \\( -iname '*.tif' -o -iname '*.tiff' \\) ! -iname '*_thumb*' \\
        | sort > filelist.txt

    if [ ! -s filelist.txt ]; then
        echo "No full-resolution .tif images found under ${plate}" >&2
        exit 1
    fi

    cellprofiler -c -r -p ${cppipe} --file-list filelist.txt -o measurements
    """

    // STUB: don't run CellProfiler — show the command and fake an output (use `-stub-run`).
    stub:
    """
    mkdir -p measurements dp_metadata
    find -L ${plate} -type f \\( -iname '*.tif' -o -iname '*.tiff' \\) ! -iname '*_thumb*' \\
        | sort > filelist.txt
    echo "cellprofiler -c -r -p ${cppipe} --file-list filelist.txt -o measurements" \\
        > measurements/cmd.txt
    touch measurements/${plate_id}.sqlite
    """
}
