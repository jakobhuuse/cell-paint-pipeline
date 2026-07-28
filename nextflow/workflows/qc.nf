include { CELLPROFILER_QC } from '../modules/cellprofiler.nf'
include { plateImages; loadDataChunks } from '../utils.nf'
include { CYTOPIPE_LOADDATA; CYTOPIPE_QC_REVIEW } from '../modules/cytopipe.nf'

// Branch-agnostic quality-control pass. Run this before choosing --pipeline cellprofiler or
// deepprofiler, inspect the gallery, download an exclusion list from it, and point
// qc_exclude_file at that file on whichever branch you run next. Always uses 1_QC.cppipe
// regardless of which branch that is.
workflow QC {
    main:
    images   = plateImages()
    base_csv = CYTOPIPE_LOADDATA(images, false, params.cellprofiler_chunk_size)
    chunks   = loadDataChunks(base_csv.chunks, images)
    qc       = CELLPROFILER_QC(chunks, file(params.qc_cppipe))

    // One combined gallery across every plate in this run, not per-plate, so reviewing image
    // quality shows the whole experiment in one page.
    review = CYTOPIPE_QC_REVIEW(qc.qc.map { _plate_id, dir -> dir }.collect())

    emit:
    qc_reports = qc.qc
    gallery    = review.gallery
}
