# CLI Specification

## Purpose

The `preserf` command-line interface (Typer-based): drives the preprocessor over single files, output directories, or recursive trees, and exposes the bundled Fortran runtime and CMake helper locations to build systems.

## Requirements

### Requirement: Single-file mode
`preserf INPUT.f90 -o OUTPUT.f90` SHALL preprocess one file and write the expansion to the given output path.

#### Scenario: Explicit output file
- **WHEN** the user runs `preserf in.f90 -o out.f90`
- **THEN** `out.f90` contains the expanded source and the exit code is 0

### Requirement: Output-directory mode
`preserf INPUT.f90 -d OUTDIR/` SHALL preprocess the file and write the result into the given directory using the input's base name.

#### Scenario: Directory target
- **WHEN** the user runs `preserf src/a.f90 -d gen/`
- **THEN** `gen/a.f90` contains the expanded source

### Requirement: Recursive mode
`preserf -r -d OUT/ SRCDIR/` SHALL preprocess every supported Fortran source under the source directory tree, mirroring the directory structure under the output directory. `--recursive` SHALL require `--output-dir`.

#### Scenario: Missing output dir
- **WHEN** `--recursive` is passed without `--output-dir`
- **THEN** the CLI fails with a usage error before processing anything

### Requirement: Runtime location flags
The CLI SHALL print the absolute path of the bundled Fortran runtime sources via `--fortran-dir` and of the CMake helper via `--cmake-helper`, mirroring the Python API `preserf.get_fortran_dir()` / `preserf.get_cmake_helper()`.

#### Scenario: Build-system discovery
- **WHEN** a CMake project executes `preserf --cmake-helper`
- **THEN** stdout is the absolute path of `PreserfFortran.cmake` inside the installed package

### Requirement: Error reporting
Directive errors SHALL surface as CLI failures that print the `DirectiveError` message (file and line) and exit non-zero.

#### Scenario: Malformed directive
- **WHEN** a processed file contains a directive with a bad continuation
- **THEN** the CLI reports the file and line and exits non-zero
