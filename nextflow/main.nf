include { CELLPROFILER } from './modules/cellprofiler.nf'
include { DEEPPROFILER } from './modules/deepprofiler.nf'
include { CYTOTABLE    } from './modules/cytotable.nf'
include { PYCYTOMINER  } from './modules/pycytominer.nf'

params.input_dir  = 'testdata/'
params.plate_glob = '*/*'
params.cppipe     = "conf/cellprofiler/pipeline.cppipe"

workflow {
    plates = channel.fromPath("${params.input_dir}/${params.plate_glob}", type: 'dir')
        .map { dir -> tuple(dir.name, dir) }   // (plate_id, plate_dir)

    // Stage 1: CellProfiler (image-based measurements + per-site outputs).
    CELLPROFILER(plates, file(params.cppipe ?: 'NO_CPPIPE'))

    // Stage 2: CytoTable -> single-cell parquet (CellProfiler branch).
    //CYTOTABLE(CELLPROFILER.out.measurements)

    // Stage 3: pycytominer -> aggregated/normalized profiles.
    //PYCYTOMINER(CYTOTABLE.out.single_cell, file(params.platemap ?: 'NO_PLATEMAP'))

    //DEEPPROFILER(CELLPROFILER.out.dp_metadata, file(params.dp_config ?: 'NO_DPCONFIG'))
}
