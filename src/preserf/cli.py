"""Command-line interface for the preserf preprocessor."""

import os
import sys
from collections.abc import Callable
from pathlib import Path
from typing import Annotated

import typer
from rich.console import Console
from rich.markup import escape
from rich.panel import Panel

from preserf import __version__
from preserf.errors import DirectiveError
from preserf.fortran_dist import get_cmake_helper, get_fortran_dir
from preserf.preprocessor import Options, Preprocessor

# Extensions treated as Fortran source when expanding a directory. Covers the
# free-form (.f90/.f95/.f03/.f08) and fixed-form (.f/.f77/.for) standards plus
# the include-file conventions used in the wild (.inc/.incf).
_FORTRAN_SUFFIXES = frozenset(
    {".f90", ".f95", ".f03", ".f08", ".f", ".f77", ".for", ".inc", ".incf"}
)

# Diagnostics and progress go to stderr so they never corrupt the
# preprocessed source written to stdout.
_err = Console(stderr=True)

app = typer.Typer(
    add_completion=False,
    help="Expand !$SER serialization directives in Fortran source.",
)


def _fail(message: str) -> typer.Exit:
    """Print a one-line error to stderr; the returned Exit is raised."""
    # soft_wrap keeps the diagnostic on one physical line (the terminal
    # may still fold it visually, but no newline is ever emitted).
    _err.print(f"[bold red]preserf:[/] {escape(message)}", soft_wrap=True)
    return typer.Exit(1)


def _warn(message: str) -> None:
    """Print a one-line warning to stderr; processing continues."""
    _err.print(f"[bold yellow]preserf:[/] {escape(message)}", soft_wrap=True)


def _version_callback(value: bool) -> None:
    if value:
        # Same bare-print rationale as the path callbacks below: no
        # width-based wrapping, so command substitution stays clean.
        print(f"preserf {__version__}")
        raise typer.Exit()


def _make_path_callback(getter: Callable[[], Path]) -> Callable[[bool], None]:
    # A bare ``print`` (not the rich Console) keeps the path on one line with
    # no width-based soft-wrapping, so ``$(preserf --fortran-dir)`` captures a
    # clean, single-token path.
    def _callback(value: bool) -> None:
        if value:
            print(getter())
            raise typer.Exit()

    return _callback


_fortran_dir_callback = _make_path_callback(get_fortran_dir)
_cmake_helper_callback = _make_path_callback(get_cmake_helper)


def _is_fortran(path: Path) -> bool:
    return path.suffix.lower() in _FORTRAN_SUFFIXES


def _require_readable_tree(root: Path) -> None:
    """Abort with a named path when any directory under ``root`` is unreadable.

    ``rglob`` silently prunes directories it cannot list, so an unreadable
    subtree would otherwise drop its files without any diagnostic.
    """

    def _raise(err: OSError) -> None:
        raise err

    for _dirpath, _dirnames, _filenames in os.walk(root, onerror=_raise):
        pass


def _collect(sources: list[Path], recursive: bool) -> list[Path]:
    """Resolve CLI inputs to a flat list of Fortran source files.

    Raises :class:`ValueError` if a directory is given without ``--recursive``.
    """
    files: list[Path] = []
    for path in sources:
        if path.is_dir():
            if not recursive:
                raise ValueError(f"{path} is a directory (use --recursive)")
            _require_readable_tree(path)
            files.extend(
                sorted(p for p in path.rglob("*") if p.is_file() and _is_fortran(p))
            )
        else:
            if not _is_fortran(path):
                _warn(f"{path} does not look like Fortran source")
            files.append(path)
    # Overlapping inputs (a directory and a subdirectory of it, symlinks,
    # ".." segments) can name the same file; de-duplicate by resolved
    # identity while keeping each file's first-seen path spelling.
    seen: dict[Path, Path] = {}
    for file in files:
        seen.setdefault(file.resolve(), file)
    return list(seen.values())


def _output_path(
    source: Path,
    output: Path | None,
    output_dir: Path | None,
    recursive: bool,
    roots: list[Path],
) -> Path | None:
    """Destination for ``source``, or ``None`` to write to stdout.

    ``roots`` holds the input directory roots, already filtered to
    directories by the caller; a non-directory argument can never be an
    ancestor of a collected file.
    """
    if output is not None:
        return output
    if output_dir is None:
        return None
    if recursive:
        for root in roots:
            if root in source.parents:
                return output_dir / source.relative_to(root)
    return output_dir / source.name


def _process_file(
    source: Path, destination: Path | None, options: Options, ignore_identical: bool
) -> Path | None:
    """Preprocess ``source``; return the destination written, or ``None``
    when the result went to stdout or was skipped as identical.
    """
    result = Preprocessor(str(source), source.read_text(), options).process()
    if destination is None:
        sys.stdout.write(result)
        return None
    if ignore_identical and destination.is_file():
        try:
            existing = destination.read_text()
        except UnicodeDecodeError as exc:
            # The comparison target — not the input — is undecodable, so
            # the diagnostic must name it; route it through the OSError
            # arm, which prints the message verbatim.
            raise OSError(f"{destination}: {exc}") from exc
        if existing == result:
            return None
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(result)
    return destination


@app.command()
def main(
    sources: Annotated[
        list[Path],
        typer.Argument(
            metavar="SOURCE...",
            show_default=False,
            help="Fortran source files, or directories with --recursive.",
        ),
    ],
    output: Annotated[
        Path | None,
        typer.Option(
            "-o",
            "--output",
            help="Write a single input's result here (default: stdout).",
        ),
    ] = None,
    output_dir: Annotated[
        Path | None,
        typer.Option(
            "-d",
            "--output-dir",
            help="Directory to write preprocessed files into.",
        ),
    ] = None,
    recursive: Annotated[
        bool,
        typer.Option(
            "-r",
            "--recursive",
            help="Recurse into input directories, mirroring the tree.",
        ),
    ] = False,
    ignore_identical: Annotated[
        bool,
        typer.Option(
            "-i",
            "--ignore-identical",
            help="Skip writing output identical to the existing file.",
        ),
    ] = False,
    no_prefix: Annotated[
        bool,
        typer.Option(
            "-p",
            "--no-prefix",
            help="Do not emit the '#define ACC_PREFIX !$acc' line.",
        ),
    ] = False,
    acc_if: Annotated[
        str,
        typer.Option(
            "-a",
            "--acc-if",
            help="IF clause appended to generated OpenACC update directives.",
        ),
    ] = "",
    sp_as_var: Annotated[
        bool,
        typer.Option(
            "-s",
            "--sp-as-var",
            help="Pass savepoint names as variables, not string literals.",
        ),
    ] = False,
    modules: Annotated[
        str,
        typer.Option(
            "-m",
            "--modules",
            help="Comma-separated extra modules to add to USE statements.",
        ),
    ] = "",
    ifdef: Annotated[
        str,
        typer.Option(
            "--ifdef",
            help="C-preprocessor guard symbol (empty disables guards).",
        ),
    ] = "SERIALIZE",
    real: Annotated[
        str,
        typer.Option(
            "--real",
            help="Fortran real kind parameter used by the ZERO directive.",
        ),
    ] = "ireals",
    module: Annotated[
        str,
        typer.Option(
            "--module",
            help="Module imported for fs_* serialization calls.",
        ),
    ] = "m_serialize",
    version: Annotated[
        bool,
        typer.Option(
            "--version",
            callback=_version_callback,
            is_eager=True,
            help="Show the version and exit.",
        ),
    ] = False,
    fortran_dir: Annotated[
        bool,
        typer.Option(
            "--fortran-dir",
            callback=_fortran_dir_callback,
            is_eager=True,
            help="Print the bundled Fortran runtime directory and exit.",
        ),
    ] = False,
    cmake_helper: Annotated[
        bool,
        typer.Option(
            "--cmake-helper",
            callback=_cmake_helper_callback,
            is_eager=True,
            help="Print the bundled CMake helper module path and exit.",
        ),
    ] = False,
) -> None:
    """Expand !$SER serialization directives in Fortran source."""
    options = Options(
        ifdef=ifdef,
        real=real,
        module=module,
        acc_prefix=not no_prefix,
        acc_if=acc_if,
        sp_as_var=sp_as_var,
        modules=tuple(m.strip() for m in modules.split(",") if m.strip()),
    )

    if output is not None and output_dir is not None:
        raise _fail("--output and --output-dir are mutually exclusive")

    if recursive and output_dir is None:
        raise _fail("--recursive requires --output-dir")

    try:
        files = _collect(sources, recursive)
        dir_roots = [root for root in sources if root.is_dir()]
    except (ValueError, OSError) as exc:
        raise _fail(str(exc)) from exc

    if output is not None and len(files) > 1:
        raise _fail("--output requires a single input file")

    if output is None and output_dir is None and len(files) > 1:
        raise _fail("multiple inputs require --output or --output-dir")

    written: list[Path] = []
    for source in files:
        destination = _output_path(source, output, output_dir, recursive, dir_roots)
        try:
            wrote = _process_file(source, destination, options, ignore_identical)
        except DirectiveError as exc:
            _err.print(
                Panel(
                    escape(str(exc)),
                    title="!$SER directive error",
                    border_style="red",
                    expand=False,
                )
            )
            raise typer.Exit(1) from exc
        except OSError as exc:
            raise _fail(str(exc)) from exc
        except UnicodeDecodeError as exc:
            # Undecodable input bytes fail as a one-line diagnostic instead
            # of an unhandled traceback.
            raise _fail(f"{source}: {exc}") from exc
        if wrote:
            written.append(wrote)

    for dest in written:
        _err.print(f"[green]wrote[/] {escape(str(dest))}")


if __name__ == "__main__":
    app()
