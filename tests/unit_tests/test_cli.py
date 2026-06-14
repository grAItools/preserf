"""Tests for the preserf CLI."""

from pathlib import Path

import pytest
from typer.testing import CliRunner

import preserf
from preserf.cli import _collect, app

runner = CliRunner()

_SOURCE = "module m\n!$SER ON\nend module m\n"


def test_version_string() -> None:
    assert preserf.__version__ == "0.1.0"


def test_version_flag() -> None:
    result = runner.invoke(app, ["--version"])
    assert result.exit_code == 0
    assert "0.1.0" in result.stdout


def test_no_inputs_is_error() -> None:
    result = runner.invoke(app, [])
    assert result.exit_code != 0


def test_fortran_dir_flag() -> None:
    # Prints the bundled runtime path and exits 0 without requiring SOURCE
    # args, so a build system can capture `$(preserf --fortran-dir)`.
    result = runner.invoke(app, ["--fortran-dir"])
    assert result.exit_code == 0
    out = result.stdout.strip()
    assert Path(out).is_dir()
    assert (Path(out) / "m_preserf.F90").is_file()


def test_cmake_helper_flag() -> None:
    result = runner.invoke(app, ["--cmake-helper"])
    assert result.exit_code == 0
    out = result.stdout.strip()
    assert out.endswith("PreserfFortran.cmake")
    assert Path(out).is_file()


def test_processes_file_to_stdout(tmp_path: Path) -> None:
    src = tmp_path / "in.f90"
    src.write_text(_SOURCE)
    result = runner.invoke(app, [str(src)])
    assert result.exit_code == 0
    assert "call fs_enable_serialization()" in result.stdout
    assert "#ifdef SERIALIZE" in result.stdout


def test_writes_output_file(tmp_path: Path) -> None:
    src = tmp_path / "in.f90"
    src.write_text(_SOURCE)
    dst = tmp_path / "out.f90"
    result = runner.invoke(app, [str(src), "-o", str(dst)])
    assert result.exit_code == 0
    assert "call fs_enable_serialization()" in dst.read_text()


def test_output_dir(tmp_path: Path) -> None:
    src = tmp_path / "in.f90"
    src.write_text(_SOURCE)
    out_dir = tmp_path / "generated"
    result = runner.invoke(app, [str(src), "-d", str(out_dir)])
    assert result.exit_code == 0
    assert (out_dir / "in.f90").is_file()


def test_directive_error_returns_1(tmp_path: Path) -> None:
    src = tmp_path / "bad.f90"
    src.write_text("!$SER BOGUS\n")
    result = runner.invoke(app, [str(src)])
    assert result.exit_code == 1
    assert "Unknown directive" in result.stderr


def test_missing_file_returns_1(tmp_path: Path) -> None:
    result = runner.invoke(app, [str(tmp_path / "missing.f90")])
    assert result.exit_code == 1


def test_output_with_multiple_inputs_rejected(tmp_path: Path) -> None:
    a = tmp_path / "a.f90"
    b = tmp_path / "b.f90"
    a.write_text(_SOURCE)
    b.write_text(_SOURCE)
    result = runner.invoke(app, [str(a), str(b), "-o", str(tmp_path / "o.f90")])
    assert result.exit_code == 1
    assert "single input" in result.stderr


def test_output_with_recursive_dir_rejected(tmp_path: Path) -> None:
    src = tmp_path / "src"
    src.mkdir()
    (src / "a.f90").write_text(_SOURCE)
    (src / "b.f90").write_text(_SOURCE)
    out_dir = tmp_path / "out"
    result = runner.invoke(
        app, [str(src), "-r", "-d", str(out_dir), "-o", str(tmp_path / "o.f90")]
    )
    assert result.exit_code == 1
    assert "single input" in result.stderr


def test_recursive_requires_output_dir(tmp_path: Path) -> None:
    result = runner.invoke(app, [str(tmp_path), "-r"])
    assert result.exit_code == 1
    assert "requires --output-dir" in result.stderr


def test_recursive_mirrors_tree(tmp_path: Path) -> None:
    nested = tmp_path / "src" / "sub"
    nested.mkdir(parents=True)
    (nested / "deep.f90").write_text(_SOURCE)
    (tmp_path / "src" / "top.f90").write_text(_SOURCE)
    out_dir = tmp_path / "out"
    result = runner.invoke(app, [str(tmp_path / "src"), "-r", "-d", str(out_dir)])
    assert result.exit_code == 0
    assert (out_dir / "top.f90").is_file()
    assert (out_dir / "sub" / "deep.f90").is_file()


def test_ignore_identical_skips_rewrite(tmp_path: Path) -> None:
    src = tmp_path / "in.f90"
    src.write_text(_SOURCE)
    dst = tmp_path / "out.f90"
    assert runner.invoke(app, [str(src), "-o", str(dst)]).exit_code == 0
    first_mtime = dst.stat().st_mtime_ns
    assert runner.invoke(app, [str(src), "-o", str(dst), "-i"]).exit_code == 0
    assert dst.stat().st_mtime_ns == first_mtime


def test_modules_arg_is_trimmed(tmp_path: Path) -> None:
    # Untrimmed entries would yield invalid "USE  b_mod" with a double space.
    src = tmp_path / "m.f90"
    src.write_text(_SOURCE)
    result = runner.invoke(app, [str(src), "--modules", "a_mod, b_mod ,c_mod"])
    assert result.exit_code == 0
    assert "USE a_mod\n" in result.stdout
    assert "USE b_mod\n" in result.stdout
    assert "USE c_mod\n" in result.stdout


def test_collect_deduplicates_overlapping_dirs(tmp_path: Path) -> None:
    sub = tmp_path / "src" / "sub"
    sub.mkdir(parents=True)
    (sub / "a.f90").write_text(_SOURCE)
    files = _collect([tmp_path / "src", sub], recursive=True)
    assert len(files) == 1


def test_collect_deduplicates_via_resolved_identity(tmp_path: Path) -> None:
    src = tmp_path / "src"
    src.mkdir()
    (src / "a.f90").write_text(_SOURCE)
    aliased = tmp_path / "src" / ".." / "src"
    files = _collect([src, aliased], recursive=True)
    assert len(files) == 1


def test_collect_directory_without_recursive_rejected(tmp_path: Path) -> None:
    # A directory input without --recursive is a usage error surfaced as a
    # ValueError that the CLI maps to exit code 1 (see test below).
    src = tmp_path / "src"
    src.mkdir()
    (src / "a.f90").write_text(_SOURCE)
    with pytest.raises(ValueError, match="use --recursive"):
        _collect([src], recursive=False)


def test_cli_directory_without_recursive(tmp_path: Path) -> None:
    # End-to-end: the ValueError from _collect becomes a clean exit 1 with a
    # diagnostic, not a traceback.
    src = tmp_path / "src"
    src.mkdir()
    (src / "a.f90").write_text(_SOURCE)
    result = runner.invoke(app, [str(src)])
    assert result.exit_code == 1
    assert "use --recursive" in result.stderr


def test_collect_skips_non_fortran_extension(tmp_path: Path) -> None:
    # Recursing a directory must pick up Fortran sources and skip everything
    # else (a .txt sibling here), so non-source files aren't preprocessed.
    src = tmp_path / "src"
    src.mkdir()
    (src / "a.f90").write_text(_SOURCE)
    (src / "notes.txt").write_text("not fortran\n")
    files = _collect([src], recursive=True)
    assert [f.name for f in files] == ["a.f90"]


# --- CLI flags exercised end-to-end through the typer plumbing -------------
#
# Each flag is tested only at the Options level elsewhere; these assert that
# the flag actually reaches the generated output via the CLI. The source
# names a field/savepoint distinct from any module name so a `--module foo`
# match cannot be confused with a same-named identifier in the body.
_FLAG_SOURCE = (
    "subroutine s(x)\n"
    "real, intent(in) :: x\n"
    "!$SER ON\n"
    "!$SER ZERO fld\n"
    "!$SER SAVEPOINT step\n"
    "!$SER ACCDATA data=x\n"
    "end subroutine s\n"
)


def _run_source(tmp_path: Path, source: str, *flags: str) -> str:
    src = tmp_path / "in.f90"
    src.write_text(source)
    result = runner.invoke(app, [str(src), *flags])
    assert result.exit_code == 0, result.stdout
    return result.stdout


def test_cli_module_flag(tmp_path: Path) -> None:
    # --module / Options.module: the fs_* USE import targets the named module.
    out = _run_source(tmp_path, _FLAG_SOURCE, "--module", "foo")
    assert "USE foo, ONLY:" in out
    assert "USE m_serialize" not in out


def test_cli_module_flag_default(tmp_path: Path) -> None:
    # Default Options.module is m_serialize when --module is omitted.
    out = _run_source(tmp_path, _FLAG_SOURCE)
    assert "USE m_serialize, ONLY:" in out


def test_cli_no_prefix_flag(tmp_path: Path) -> None:
    # --no-prefix suppresses the `#define ACC_PREFIX !$acc` header line.
    assert "#define ACC_PREFIX !$acc" in _run_source(tmp_path, _FLAG_SOURCE)
    assert "#define ACC_PREFIX" not in _run_source(
        tmp_path, _FLAG_SOURCE, "--no-prefix"
    )


def test_cli_acc_if_flag(tmp_path: Path) -> None:
    # --acc-if appends an IF clause to generated OpenACC UPDATE directives.
    out = _run_source(tmp_path, _FLAG_SOURCE, "--acc-if", "lacc")
    assert "ACC_PREFIX UPDATE HOST ( x ), IF (lacc)" in out


def test_cli_sp_as_var_flag(tmp_path: Path) -> None:
    # --sp-as-var passes the savepoint name as a bare variable, not a literal.
    assert "fs_create_savepoint('step'," in _run_source(tmp_path, _FLAG_SOURCE)
    assert "fs_create_savepoint(step," in _run_source(
        tmp_path, _FLAG_SOURCE, "--sp-as-var"
    )


def test_cli_ifdef_flag(tmp_path: Path) -> None:
    # --ifdef changes the C-preprocessor guard symbol from the default.
    out = _run_source(tmp_path, _FLAG_SOURCE, "--ifdef", "MYGUARD")
    assert "#ifdef MYGUARD" in out
    assert "#ifdef SERIALIZE" not in out


def test_cli_real_flag(tmp_path: Path) -> None:
    # --real sets the real kind parameter the ZERO directive emits.
    out = _run_source(tmp_path, _FLAG_SOURCE, "--real", "wp")
    assert "fld = 0.0_wp" in out
