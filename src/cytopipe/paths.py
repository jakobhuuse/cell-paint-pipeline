"""Path helpers shared across cytopipe commands.

Stage I/O is explicit (passed in by Nextflow), so these helpers only validate and
normalise paths — they do not encode any shared/implicit data-root convention.
"""

from __future__ import annotations

from pathlib import Path


def resolve_input(path: Path) -> Path:
    """Resolve an existing input path or raise."""
    resolved = path.expanduser().resolve()
    if not resolved.exists():
        raise FileNotFoundError(f"Input path does not exist: {resolved}")
    return resolved


def prepare_output(path: Path) -> Path:
    """Resolve an output path and ensure its parent directory exists."""
    resolved = path.expanduser().resolve()
    resolved.parent.mkdir(parents=True, exist_ok=True)
    return resolved
