# Tasks

## 1. Boundary tests (fail first)

- [x] 1.1 Add parametrized CLI cases for empty files, CRLF-terminated sources, and non-UTF-8 bytes, asserting the pinned outcome for each

## 2. Marker and lane wiring

- [x] 2.1 Declare the `packaging` marker in `pyproject.toml` and extend the default deselection to `-m 'not consumer and not packaging'` (the conjunction form; the space-separated shorthand is not valid pytest syntax)
- [x] 2.2 Mark the wheel/sdist construction tests in `tests/integration_tests/test_packaging_distribution.py` with the new marker
- [x] 2.3 Add a dedicated `test-packaging` pixi lane (`pytest -m packaging`) and wire it into `verify`'s depends-on so the artifact-build tests stay gated end to end

## 3. Documentation

- [x] 3.1 Correct the fast-loop speed claims in `dev/testing.md:12` to the measured numbers
- [x] 3.2 Correct the stale sub-second claim in the wire-compat docstring (`tests/integration_tests/test_fortran_wire_compat.py:7-9`)

## 4. Verification

- [x] 4.1 Add the CHANGELOG bullet under `[Unreleased]`
- [x] 4.2 Run `pixi run verify` and confirm it is green
