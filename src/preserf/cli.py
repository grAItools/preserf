"""Command-line interface for the preserf preprocessor."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from preserf.errors import DirectiveError
from preserf.preprocessor import Options, Preprocessor

# File extensions treated as Fortran source.
_FORTRAN_SUFFIXES = frozenset({".f90", ".f", ".f03", ".inc", ".incf"})


def _get_version() -> str:
    from preserf import __version__

    return __version__


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="preserf",
        description="A preprocessor for Fortran data serialization directives",
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"%(prog)s {_get_version()}",
    )
    parser.add_argument(
        "inputs",
        nargs="*",
        metavar="SOURCE",
        help="Fortran source files (or directories with --recursive)",
    )
    parser.add_argument(
        "-o",
        "--output",
        metavar="FILE",
        default="",
        help="output file (single input only); default is stdout",
    )
    parser.add_argument(
        "-d",
        "--output-dir",
        metavar="DIR",
        default="",
        help="directory to write preprocessed files into",
    )
    parser.add_argument(
        "-r",
        "--recursive",
        action="store_true",
        help="recurse into input directories, mirroring the tree",
    )
    parser.add_argument(
        "-i",
        "--ignore-identical",
        action="store_true",
        help="skip writing output that is identical to the existing file",
    )
    parser.add_argument(
        "-p",
        "--no-prefix",
        dest="acc_prefix",
        action="store_false",
        help="do not emit the '#define ACC_PREFIX !$acc' line",
    )
    parser.add_argument(
        "-a",
        "--acc-if",
        metavar="EXPR",
        default="",
        help="IF clause appended to generated OpenACC update directives",
    )
    parser.add_argument(
        "-s",
        "--sp-as-var",
        action="store_true",
        help="pass savepoint names as variables instead of string literals",
    )
    parser.add_argument(
        "-m",
        "--modules",
        metavar="MODS",
        default="",
        help="comma-separated extra modules to add to USE statements",
    )
    parser.add_argument(
        "--ifdef",
        metavar="SYMBOL",
        default="SERIALIZE",
        help="C-preprocessor guard symbol (empty disables guards)",
    )
    parser.add_argument(
        "--real",
        metavar="KIND",
        default="ireals",
        help="Fortran real kind parameter used by the ZERO directive",
    )
    parser.add_argument(
        "--module",
        metavar="NAME",
        default="m_serialize",
        help="module imported for fs_* serialization calls",
    )
    return parser.parse_args(argv)


def _options(args: argparse.Namespace) -> Options:
    return Options(
        ifdef=args.ifdef,
        real=args.real,
        module=args.module,
        acc_prefix=args.acc_prefix,
        acc_if=args.acc_if,
        sp_as_var=args.sp_as_var,
        modules=tuple(m.strip() for m in args.modules.split(",") if m.strip()),
    )


def _is_fortran(path: Path) -> bool:
    return path.suffix.lower() in _FORTRAN_SUFFIXES


def _collect(inputs: list[str], recursive: bool) -> list[Path]:
    """Resolve CLI inputs to a flat list of Fortran source files.

    Raises :class:`ValueError` if a directory is given without ``--recursive``.
    """
    files: list[Path] = []
    for raw in inputs:
        path = Path(raw)
        if path.is_dir():
            if not recursive:
                raise ValueError(f"{raw} is a directory (use --recursive)")
            files.extend(
                sorted(p for p in path.rglob("*") if p.is_file() and _is_fortran(p))
            )
        else:
            files.append(path)
    # Overlapping inputs (e.g. a directory and a subdirectory of it) can
    # resolve to the same file; de-duplicate while preserving order.
    return list(dict.fromkeys(files))


def _output_path(
    source: Path, args: argparse.Namespace, roots: list[str]
) -> Path | None:
    """Destination for ``source``, or ``None`` to write to stdout."""
    if args.output:
        return Path(args.output)
    if not args.output_dir:
        return None
    out_dir = Path(args.output_dir)
    if args.recursive:
        for raw in roots:
            root = Path(raw)
            if root.is_dir() and root in source.parents:
                return out_dir / source.relative_to(root)
    return out_dir / source.name


def _process_file(
    source: Path, destination: Path | None, options: Options, ignore_identical: bool
) -> None:
    text = source.read_text()
    result = Preprocessor(str(source), text, options).process()
    if destination is None:
        sys.stdout.write(result)
        return
    if ignore_identical and destination.is_file() and destination.read_text() == result:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(result)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if not args.inputs:
        print("preserf: no input files", file=sys.stderr)
        return 1
    if args.recursive and not args.output_dir:
        print("preserf: --recursive requires --output-dir", file=sys.stderr)
        return 1

    options = _options(args)
    try:
        files = _collect(args.inputs, args.recursive)
    except ValueError as exc:
        print(f"preserf: {exc}", file=sys.stderr)
        return 1

    if args.output and len(files) > 1:
        print("preserf: --output requires a single input file", file=sys.stderr)
        return 1

    for source in files:
        destination = _output_path(source, args, args.inputs)
        try:
            _process_file(source, destination, options, args.ignore_identical)
        except DirectiveError as exc:
            print(exc, file=sys.stderr)
            return 1
        except OSError as exc:
            print(f"preserf: {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
