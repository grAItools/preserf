# Tasks

## 1. Tests (fail first)

- [ ] 1.1 Add a `consumer`-marked test that installs the built wheel into a venv under `tmp_path` and drives the existing consumer CMake recipe against that install's `preserf --cmake-helper`
- [ ] 1.2 Add an assertion that the built wheel's `METADATA` `Version:` equals `preserf.__version__`
- [ ] 1.3 Extend `_EXPECTED_RUNTIME_FILES` with `preserf/py.typed` and `preserf/fortran/README.md`

## 2. Dependencies and configuration

- [ ] 2.1 Add `twine = ">=6"` to `[feature.dev.pypi-dependencies]` (`pixi.toml:22-32`) and re-lock
- [ ] 2.2 Confirm the skipif in `test_packaging_distribution.py:132-148` no longer fires and `twine check` executes on both artifacts

## 3. Documentation

- [ ] 3.1 State the POSIX-only Fortran runtime prerequisite in the root README's build section
- [ ] 3.2 Rewrite the shipped runtime README's repo-relative links as absolute repository URLs (`src/preserf/fortran/README.md:5`, `:42`)

## 4. Verification

- [ ] 4.1 Add the CHANGELOG bullet under `[Unreleased]`
- [ ] 4.2 Run `pixi run verify` and `pixi run test-consumer` and confirm both are green
