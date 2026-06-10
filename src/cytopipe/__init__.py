"""cytopipe — CytoTable-based data-management/glue layer for the cell-painting pipeline."""

from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("cytopipe")
except PackageNotFoundError:  # not installed (e.g. running from source tree)
    __version__ = "0.0.0"
