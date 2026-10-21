# Spec Delta

## Purpose

Execute the wheel-to-install-to-consume chain and the distribution metadata gates instead of inferring them from content inspection and editable-install tests.

## MODIFIED Requirements

### Requirement: Wheel contents

The wheel SHALL include the Fortran runtime sources and the CMake helper module as package data, so a `pip install preserf` consumer can compile preserf-generated Fortran without cloning this repository. Prebuilt libraries and compiler-specific `.mod` files SHALL NOT be distributed. The packaged runtime README and the `py.typed` marker SHALL be asserted as part of the wheel's expected contents.

#### Scenario: Fresh consumer project

- **WHEN** a project depends only on the installed `preserf` package and calls `preserf.get_fortran_dir()`
- **THEN** it receives the runtime sources and compiles them against its own netcdf-fortran

#### Scenario: Typing and docs payload

- **WHEN** the wheel contents are asserted
- **THEN** `preserf/py.typed` and `preserf/fortran/README.md` are among the expected files

### Requirement: Distribution metadata

The package metadata SHALL derive its version from a single literal in `src/preserf/__init__.py` (hatch reads it), target Python >= 3.12, and declare runtime dependencies `typer>=0.12` and `rich>=13.0` only. Built artifacts SHALL pass `twine check` with the validation tool installed in the development environment, and the wheel's `METADATA` version SHALL be asserted equal to `preserf.__version__`.

#### Scenario: Version bump

- **WHEN** the version literal in `__init__.py` is bumped
- **THEN** the wheel metadata and `importlib.metadata.version("preserf")` reflect it without any other edit

#### Scenario: Metadata validation runs

- **WHEN** the packaging tests run in the development environment
- **THEN** `twine check` executes on both built artifacts instead of skipping

## ADDED Requirements

### Requirement: Install-and-consume verification

The packaged CMake helper SHALL be consumable from a wheel-installed `site-packages`: installing the built wheel into a clean environment and driving the documented consumer recipe SHALL compile and run a downstream project without the repository checkout.

#### Scenario: Wheel-installed consumer build

- **WHEN** the built wheel is installed into a clean virtual environment and the consumer CMake project resolves `preserf --cmake-helper` from that install
- **THEN** the downstream project builds and runs using only the installed package
