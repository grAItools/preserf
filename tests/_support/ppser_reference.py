"""Run the upstream Serialbox ``pp_ser`` preprocessor in-process.

preserf is a re-implementation of the upstream ``pp_ser.py`` preprocessor. To
validate preserf against the real thing, this helper loads ``pp_ser`` from the
installed ``serialbox4py`` distribution — a **test-only** dependency declared in
``pixi.toml`` — rather than vendoring a pinned copy in-tree (see
``docs/adr/0006-ppser-differential-dependency.md``).

``pp_ser.py`` ships inside the ``serialbox`` package at
``serialbox/python/pp_ser/pp_ser.py``, but it is *not* an importable submodule:
that directory has no ``__init__.py``, and importing the top-level ``serialbox``
package would pull in the native Serialbox runtime, which this differential test
does not need. The script itself is pure stdlib, so we locate it via the
``serialbox`` package's search path — without executing ``serialbox/__init__.py``
— and load it by path.

Exposes:

* :func:`expand_with_ppser` — expand a Fortran source string with upstream
  ``pp_ser`` and return the expanded text;
* :func:`extract_runtime_calls` — normalize an expansion (from *either* tool)
  down to its ordered sequence of generated ``call fs_*`` / ``call ppser_*``
  statements, so the two can be diffed by *serialization intent* rather than
  incidental formatting.
"""

from __future__ import annotations

import importlib.util
import re
import tempfile
import warnings
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from types import ModuleType


def _load_upstream_ppser() -> ModuleType:
    """Load ``pp_ser`` from the installed ``serialbox4py`` package, once.

    Resolves the ``serialbox`` package location with :func:`importlib.util.find_spec`
    (which does *not* execute ``serialbox/__init__.py`` and so never touches the
    native runtime), then loads the pure-stdlib ``pp_ser.py`` by path, ignoring
    its legacy Python-2-era ``SyntaxWarning``s.
    """
    pkg_spec = importlib.util.find_spec("serialbox")
    if pkg_spec is None or not pkg_spec.submodule_search_locations:
        raise RuntimeError(
            "serialbox4py is not installed; it is a test-only dependency "
            "(see docs/adr/0006-ppser-differential-dependency.md)"
        )
    pkg_dir = Path(next(iter(pkg_spec.submodule_search_locations)))
    pp_ser_path = pkg_dir / "python" / "pp_ser" / "pp_ser.py"
    spec = importlib.util.spec_from_file_location("_serialbox_pp_ser", pp_ser_path)
    if spec is None or spec.loader is None:  # pragma: no cover - defensive
        raise RuntimeError(f"cannot load pp_ser from {pp_ser_path}")
    module = importlib.util.module_from_spec(spec)
    with warnings.catch_warnings():
        # pp_ser.py predates Python 3.12's stricter escape-sequence rules.
        warnings.simplefilter("ignore", SyntaxWarning)
        spec.loader.exec_module(module)
    return module


_PPSER = _load_upstream_ppser()


def expand_with_ppser(source: str, *, real: str = "ireals") -> str:
    """Expand ``source`` with the upstream ``pp_ser``, returning text.

    ``real`` defaults to ``"ireals"`` to match preserf's :class:`Options`
    default (the ``PpSer`` class default is ``ireals``; only upstream's
    command-line ``__main__`` hard-codes ``wp``).
    """
    with tempfile.TemporaryDirectory() as tmp:
        in_path = Path(tmp) / "input.f90"
        out_path = Path(tmp) / "output.f90"
        in_path.write_text(source)
        # No SyntaxWarning suppression is needed here: those fire at compile
        # time during exec_module (handled once in _load_upstream_ppser), not
        # while running the already-loaded module.
        _PPSER.PpSer(str(in_path), outfile=str(out_path), real=real).preprocess()
        return out_path.read_text()


# Joining on bare ``&`` is sound only because both tools emit ``&`` solely as a
# continuation marker *within* a single logical statement — never as a trailing
# token whose intervening newline carries meaning. Under that assumption,
# deleting ``&\n`` runs simply reassembles each split statement onto one line.
_RE_CONTINUATION = re.compile(r"&[ \t]*\n[ \t]*&?[ \t]*")
# Match only statements that *begin* with ``call`` (after stripping leading
# whitespace), so ``call`` inside an inline ``!`` comment can't be picked up.
# Trailing inline comments are stripped separately below. Paren-less calls
# (e.g. ``call ppser_finalize``) are intentionally NOT matched: the generated
# Serialbox runtime API in the current corpus always passes arguments, so every
# emitted call has a ``(``. Revisit this if a no-argument runtime call appears.
_RE_CALL = re.compile(r"^[ \t]*(call[ \t]+\w+[ \t]*\(.*)", re.IGNORECASE)
_RE_INLINE_COMMENT = re.compile(r"!.*$")
_RE_WHITESPACE = re.compile(r"\s+")


def extract_runtime_calls(expanded: str) -> list[str]:
    """Return the ordered, whitespace-normalized ``call ...`` statements.

    Fortran ``&`` line continuations are joined first so a multi-line call
    (e.g. ``ppser_initialize``) collapses onto one logical statement. Comments,
    ``#ifdef`` guards, the injected ``USE`` block, and ``! file: lineno:``
    annotations carry no leading ``call`` and are dropped. Any trailing inline
    ``!`` comment on a ``call`` line is stripped. The result reflects which
    fields are written/read, at which savepoint, with which arguments, and in
    what order — the axis a differential test should compare.
    """
    joined = _RE_CONTINUATION.sub("", expanded)
    calls: list[str] = []
    for line in joined.splitlines():
        match = _RE_CALL.match(line)
        if match is not None:
            statement = _RE_INLINE_COMMENT.sub("", match.group(1))
            calls.append(_RE_WHITESPACE.sub(" ", statement).strip())
    return calls
