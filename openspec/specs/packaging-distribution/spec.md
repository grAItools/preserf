# Packaging and Distribution Specification

## Purpose

How preserf ships the preprocessor, the Fortran runtime sources, and the CMake helper inside the wheel, and how downstream projects consume them. `pip install preserf` is self-sufficient: no clone of this repository is needed to compile preserf-generated Fortran.

## Requirements

### Requirement: Wheel contents

The wheel SHALL include the Fortran runtime sources and the CMake helper module as package data, so a `pip install preserf` consumer can compile preserf-generated Fortran without cloning this repository. Prebuilt libraries and compiler-specific `.mod` files SHALL NOT be distributed.

#### Scenario: Fresh consumer project

- **WHEN** a project depends only on the installed `preserf` package and calls `preserf.get_fortran_dir()`
- **THEN** it receives the runtime sources and compiles them against its own netcdf-fortran

### Requirement: Location discovery API

The package SHALL expose `preserf.get_fortran_dir()` and `preserf.get_cmake_helper()` (mirrored as CLI flags `--fortran-dir` / `--cmake-helper`), following the numpy `get_include()` pattern.

#### Scenario: CMake consume

- **WHEN** a CMake project includes `$(preserf --cmake-helper)` and calls `preserf_add_fortran_target()`
- **THEN** one function drives expand, compile (with `-DSERIALIZE`), and link against the runtime and netcdf-fortran

### Requirement: Installable runtime library

The bundled `CMakeLists.txt` SHALL be a standalone, installable CMake project producing an installed `preserf_fortran` library with a package config, consumable via `find_package(preserf_fortran REQUIRED)` and `target_link_libraries(... preserf::preserf_fortran)` with transitive netcdf-fortran flags.

#### Scenario: find_package consumer

- **WHEN** the runtime is installed to a prefix and a downstream project builds with the same Fortran compiler
- **THEN** `find_package` + `target_link_libraries` compiles and links without manual include/library flags

### Requirement: Build-system agnostic recipe

Projects not using CMake SHALL be able to drive the same pipeline by hand: run `preserf` on the sources, compile with `-cpp -DSERIALIZE -std=f2008 -ffree-line-length-none -I<prefix>/include/preserf_fortran`, and link `-lpreserf_fortran` plus `pkg-config --libs netcdf-fortran`.

#### Scenario: Plain make example

- **WHEN** the laplacian example builds via its hand-written Makefile against an installed runtime
- **THEN** the same program produced by the CMake variant runs with identical results

### Requirement: Distribution metadata

The package metadata SHALL derive its version from a single literal in `src/preserf/__init__.py` (hatch reads it), target Python >= 3.12, and declare runtime dependencies `typer>=0.12` and `rich>=13.0` only.

#### Scenario: Version bump

- **WHEN** the version literal in `__init__.py` is bumped
- **THEN** the wheel metadata and `importlib.metadata.version("preserf")` reflect it without any other edit
