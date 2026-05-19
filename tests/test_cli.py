"""Tests for the preserf CLI."""

from pathlib import Path

import pytest

import preserf
from preserf.cli import _collect, _options, main, parse_args

_SOURCE = "module m\n!$SER ON\nend module m\n"


def test_version_string() -> None:
    assert preserf.__version__ == "0.1.0"


def test_parse_args_defaults() -> None:
    args = parse_args([])
    assert args.inputs == []
    assert args.ifdef == "SERIALIZE"


def test_modules_arg_is_trimmed() -> None:
    args = parse_args(["x.f90", "--modules", "a_mod, b_mod ,c_mod"])
    assert _options(args).modules == ("a_mod", "b_mod", "c_mod")


def test_version_flag_exits() -> None:
    with pytest.raises(SystemExit):
        parse_args(["--version"])


def test_main_no_inputs_returns_1(capsys: pytest.CaptureFixture[str]) -> None:
    assert main([]) == 1
    assert "no input files" in capsys.readouterr().err


def test_main_processes_file_to_stdout(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    src = tmp_path / "in.f90"
    src.write_text(_SOURCE)
    assert main([str(src)]) == 0
    out = capsys.readouterr().out
    assert "call fs_enable_serialization()" in out
    assert "#ifdef SERIALIZE" in out


def test_main_writes_output_file(tmp_path: Path) -> None:
    src = tmp_path / "in.f90"
    src.write_text(_SOURCE)
    dst = tmp_path / "out.f90"
    assert main([str(src), "-o", str(dst)]) == 0
    assert "call fs_enable_serialization()" in dst.read_text()


def test_main_output_dir(tmp_path: Path) -> None:
    src = tmp_path / "in.f90"
    src.write_text(_SOURCE)
    out_dir = tmp_path / "generated"
    assert main([str(src), "-d", str(out_dir)]) == 0
    assert (out_dir / "in.f90").is_file()


def test_main_directive_error_returns_1(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    src = tmp_path / "bad.f90"
    src.write_text("!$SER BOGUS\n")
    assert main([str(src)]) == 1
    assert "Unknown directive" in capsys.readouterr().err


def test_main_missing_file_returns_1(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert main([str(tmp_path / "missing.f90")]) == 1
    assert "preserf:" in capsys.readouterr().err


def test_main_output_with_multiple_inputs_rejected(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    a = tmp_path / "a.f90"
    b = tmp_path / "b.f90"
    a.write_text(_SOURCE)
    b.write_text(_SOURCE)
    assert main([str(a), str(b), "-o", str(tmp_path / "o.f90")]) == 1
    assert "single input" in capsys.readouterr().err


def test_main_output_with_recursive_dir_rejected(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    src = tmp_path / "src"
    src.mkdir()
    (src / "a.f90").write_text(_SOURCE)
    (src / "b.f90").write_text(_SOURCE)
    out_dir = tmp_path / "out"
    code = main([str(src), "-r", "-d", str(out_dir), "-o", str(tmp_path / "o.f90")])
    assert code == 1
    assert "single input" in capsys.readouterr().err


def test_collect_deduplicates_overlapping_dirs(tmp_path: Path) -> None:
    sub = tmp_path / "src" / "sub"
    sub.mkdir(parents=True)
    (sub / "a.f90").write_text(_SOURCE)
    files = _collect([str(tmp_path / "src"), str(sub)], recursive=True)
    assert len(files) == 1


def test_main_recursive_requires_output_dir(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assert main([str(tmp_path), "-r"]) == 1
    assert "requires --output-dir" in capsys.readouterr().err


def test_main_recursive_mirrors_tree(tmp_path: Path) -> None:
    nested = tmp_path / "src" / "sub"
    nested.mkdir(parents=True)
    (nested / "deep.f90").write_text(_SOURCE)
    (tmp_path / "src" / "top.f90").write_text(_SOURCE)
    out_dir = tmp_path / "out"
    assert main([str(tmp_path / "src"), "-r", "-d", str(out_dir)]) == 0
    assert (out_dir / "top.f90").is_file()
    assert (out_dir / "sub" / "deep.f90").is_file()


def test_main_ignore_identical_skips_rewrite(tmp_path: Path) -> None:
    src = tmp_path / "in.f90"
    src.write_text(_SOURCE)
    dst = tmp_path / "out.f90"
    assert main([str(src), "-o", str(dst)]) == 0
    first_mtime = dst.stat().st_mtime_ns
    assert main([str(src), "-o", str(dst), "-i"]) == 0
    assert dst.stat().st_mtime_ns == first_mtime
