"""preserf - A preprocessor for Fortran data serialization directives."""

from preserf.errors import DirectiveError
from preserf.fortran_dist import get_cmake_helper, get_fortran_dir
from preserf.preprocessor import Options, Preprocessor

__version__ = "0.1.0"

__all__ = [
    "DirectiveError",
    "Options",
    "Preprocessor",
    "__version__",
    "get_cmake_helper",
    "get_fortran_dir",
]
