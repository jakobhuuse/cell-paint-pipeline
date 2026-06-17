include { CELLPROFILER_ILLUM; CELLPROFILER_CHUNKS; CELLPROFILER_ANALYSIS } from '../modules/cellprofiler.nf'
include {CYTOPIPE_CELLPROFILER_PARQUET} from '../modules/cytopipe.nf'

workflow {
    plates = channel.fromPath("${params.input_dir}/${params.plate_glob}", type: 'dir')
        .map { dir -> tuple(dir.name, dir) }

    CELLPROFILER_ILLUM(plates, file(params.illum_cppipe))
    CELLPROFILER_CHUNKS(plates)

    // (plate_id, first, last) - one row per chunk of image sets
    chunks = CELLPROFILER_CHUNKS.out.chunks
        .splitCsv(elem: 1)
        .map { plate_id, row -> tuple(plate_id, row[0] as int, row[1] as int) }

    // (plate_id, illum, plate, first, last) - one analysis task per chunk
    analysis_in = CELLPROFILER_ILLUM.out.illum
        .join(plates)
        .combine(chunks, by: 0)

    CELLPROFILER_ANALYSIS(analysis_in, file(params.analysis_cppipe))

    // gather the per-chunk sqlite files back into one group per plate
    measurements = CELLPROFILER_ANALYSIS.out.measurement.groupTuple()

    CYTOPIPE_CELLPROFILER_PARQUET(measurements)
}
