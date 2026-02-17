"""Command-line interface for preserf."""

import argparse
import sys


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
    return parser.parse_args(argv)


def _get_version() -> str:
    from preserf import __version__

    return __version__


def main(argv: list[str] | None = None) -> int:
    parse_args(argv)
    return 0


if __name__ == "__main__":
    sys.exit(main())
