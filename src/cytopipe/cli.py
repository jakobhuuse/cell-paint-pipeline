"""cytopipe Typer CLI.

Exposes only the glue steps owned by this package:

- ``convert`` — CytoTable conversion of image-tool output into single-cell parquet.
- ``bridge``  — CellProfiler -> DeepProfiler metadata/segmentation handoff.

CellProfiler, DeepProfiler, and pycytominer run via their own container images'
native entrypoints (driven by Nextflow), not through this CLI.
"""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

app = typer.Typer(
    help="CytoTable-based glue layer for the cell-painting pipeline.",
    no_args_is_help=True,
    add_completion=False,
)


@app.command()
def convert(
    source: Annotated[
        Path,
        typer.Option("--source", "-s", help="CellProfiler output (.sqlite file or CSV dir)."),
    ],
    dest: Annotated[
        Path,
        typer.Option("--dest", "-d", help="Output single-cell parquet path."),
    ],
    preset: Annotated[
        str,
        typer.Option(help="CytoTable preset matching the source format."),
    ] = "cellprofiler_sqlite",
    join: Annotated[
        bool,
        typer.Option(help="Merge per-compartment tables into one single-cell table."),
    ] = True,
) -> None:
    """Convert image-tool output into a single-cell parquet (CytoTable)."""
    from cytopipe.convert import run_convert

    out = run_convert(source, dest, preset=preset, join=join)  # type: ignore[arg-type]
    typer.echo(f"Wrote {out}")


@app.command()
def bridge(
    cellprofiler_output: Annotated[
        Path,
        typer.Option("--cp-output", help="Directory of CellProfiler per-site outputs."),
    ],
    platemap: Annotated[
        Path,
        typer.Option("--platemap", help="Platemap CSV (well -> perturbation/label)."),
    ],
    dest: Annotated[
        Path,
        typer.Option("--dest", "-d", help="Directory to write DeepProfiler metadata into."),
    ],
) -> None:
    """Build DeepProfiler metadata from CellProfiler output (CP -> DP handoff)."""
    from cytopipe.bridge import build_metadata

    out = build_metadata(cellprofiler_output, platemap, dest)
    typer.echo(f"Wrote {out}")


if __name__ == "__main__":
    app()
