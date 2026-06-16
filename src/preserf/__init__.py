"""preserf - A preprocessor for Fortran data serialization directives."""

from preserf.errors import DirectiveError
from preserf.fortran_dist import get_cmake_helper, get_fortran_dir
from preserf.preprocessor import Options, Preprocessor

# Single source of truth for the project version. `pyproject.toml`'s
# `[tool.hatch.version]` reads this literal at build time, so the wheel
# metadata and `importlib.metadata.version("preserf")` derive from it.
# Bump this one line to release; CHANGELOG.md tracks the same value.
__version__ = "0.2.0.dev0"

__all__ = [
    "DirectiveError",
    "Options",
    "Preprocessor",
    "__version__",
    "get_cmake_helper",
    "get_fortran_dir",
]
