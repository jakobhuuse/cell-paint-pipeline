include { CELLPROFILER_ILLUM; CP_CHUNK_TASKS; CELLPROFILER_DEEPPROFILER } from '../modules/cellprofiler.nf'
include { CYTOPIPE_CELLPROFILER_DEEPPROFILER; CYTOPIPE_DEEPPROFILER_PARQUET } from '../modules/cytopipe.nf'
include { DEEPPROFILER_PROFILE } from '../modules/deepprofiler.nf'

workflow {
    plates = channel.fromPath("${params.input_dir}/${params.plate_glob}", type: 'dir')
        .map { dir -> tuple(dir.name, dir) }

    platemap = file("${params.input_dir}/platemap.csv", checkIfExists: true)

    CELLPROFILER_ILLUM(plates, file(params.illum_cppipe))

    // per-chunk CellProfiler segmentation (same chunking as analysis)
    CP_CHUNK_TASKS(plates, CELLPROFILER_ILLUM.out.illum)

    CELLPROFILER_DEEPPROFILER(CP_CHUNK_TASKS.out, file(params.deepprofiler_cppipe))

    // Gather per-chunk outputs back per plate. Image.csv is concatenated (single header);
    // location CSVs and corrected images carry unique well/site names, so they just union.
    image_csv = CELLPROFILER_DEEPPROFILER.out.image_csv
        .collectFile(keepHeader: true, skip: 1) { plate_id, csv -> ["${plate_id}.csv", csv] }
        .map { csv -> tuple(csv.baseName, csv) }

    locations = CELLPROFILER_DEEPPROFILER.out.locations
        .groupTuple()
        .map { plate_id, files -> tuple(plate_id, files.flatten()) }

    images = CELLPROFILER_DEEPPROFILER.out.images
        .groupTuple()
        .map { plate_id, files -> tuple(plate_id, files.flatten()) }

    CYTOPIPE_CELLPROFILER_DEEPPROFILER(image_csv.join(locations), platemap)

    profile_input = CYTOPIPE_CELLPROFILER_DEEPPROFILER.out.metadata
        .join(images)
        .map { plate_id, locations_dir, index, imgs -> tuple(plate_id, imgs, locations_dir, index) }

    DEEPPROFILER_PROFILE(
        profile_input,
        file(params.deepprofiler_config),
        file(params.deepprofiler_model)
    )

    CYTOPIPE_DEEPPROFILER_PARQUET(DEEPPROFILER_PROFILE.out.features)
}
