"""CellProfiler -> DeepProfiler metadata/segmentation handoff.

After a CellProfiler run, DeepProfiler needs an ``index.csv`` (and ``outlines.csv``)
describing each site's channels, location, and label, joined against the platemap. This
module builds those from CellProfiler's per-site outputs.

STUB: the real implementation parses CellProfiler location CSVs and the platemap; here we
only define the surface.
"""

from __future__ import annotations

from pathlib import Path

from cytopipe import paths


def build_metadata(
    cellprofiler_output: Path,
    platemap: Path,
    dest: Path,
) -> Path:
    """Build DeepProfiler ``index.csv`` (+ ``outlines.csv``) under ``dest``.

    Args:
        cellprofiler_output: Directory of CellProfiler per-site outputs (locations, outlines).
        platemap: Platemap CSV mapping wells to perturbations/labels.
        dest: Directory to write DeepProfiler metadata into.

    Returns:
        The destination directory written.
    """
    cellprofiler_output = paths.resolve_input(cellprofiler_output)
    platemap = paths.resolve_input(platemap)
    dest = paths.prepare_output(dest)

    # TODO: parse <well>_s<site>_w<channel>.tif naming, join platemap on row+col,
    #       emit index.csv / outlines.csv expected by DeepProfiler.
    raise NotImplementedError("cytopipe.bridge.build_metadata is a skeleton stub")
