"""CytoTable conversion: image-tool tabular output -> single-cell parquet.

Thin wrapper around :func:`cytotable.convert` that picks a sensible preset from the
upstream source format and injects the threaded Parsl config by default.

STUB: the call to ``cytotable.convert`` is sketched but not yet exercised against real
data. See https://cytomining.github.io/CytoTable/ for the full option set.
"""

from __future__ import annotations

from pathlib import Path
from typing import Literal

from cytopipe import paths
from cytopipe.parsl_configs import threaded

SourceFormat = Literal["cellprofiler_sqlite", "cellprofiler_csv"]


def run_convert(
    source: Path,
    dest: Path,
    *,
    preset: SourceFormat = "cellprofiler_sqlite",
    join: bool = True,
) -> Path:
    """Convert CellProfiler output at ``source`` into a single-cell parquet at ``dest``.

    Args:
        source: CellProfiler output (a ``.sqlite`` file for ``cellprofiler_sqlite``, or a
            directory of CSVs for ``cellprofiler_csv``).
        dest: Output parquet path (single file when ``join=True``).
        preset: CytoTable preset matching the upstream output format.
        join: Merge per-compartment tables into one single-cell table.

    Returns:
        The destination path written.
    """
    source = paths.resolve_input(source)
    dest = paths.prepare_output(dest)

    # TODO: wire this up and validate against real CellProfiler output.
    # from cytotable import convert
    # convert(
    #     source_path=str(source),
    #     dest_path=str(dest),
    #     dest_datatype="parquet",
    #     preset=preset,
    #     join=join,
    #     parsl_config=threaded(),
    # )
    _ = (preset, join, threaded)  # referenced so the stub keeps the intended surface
    raise NotImplementedError("cytopipe.convert.run_convert is a skeleton stub")
