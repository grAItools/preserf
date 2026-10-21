# Tasks

## 1. Tests (fail first)

- [x] 1.1 Add a CLI test that monkeypatches `rglob` to raise `OSError` and asserts the one-line diagnostic and non-zero exit (no traceback)
- [x] 1.2 Add a CLI test that two sources with neither `--output` nor `--output-dir` fail with a usage error
- [x] 1.3 Add a CLI test that an explicit non-Fortran argument emits a stderr warning and still preprocesses

## 2. Fixes

- [x] 2.1 Broaden the collection handler to `except (ValueError, OSError)` in `src/preserf/cli.py:265-268`
- [x] 2.2 Reject multi-source runs without an explicit destination before processing
- [x] 2.3 Apply `_is_fortran` to explicit file arguments and warn on mismatch
- [x] 2.4 Use bare `print` for `--version`; collapse the dead `if wrote and destination is not None:` condition in `main()` (`cli.py:290`); hoist the root `is_dir` stat out of `_output_path`'s per-file loop

## 3. Verification

- [ ] 3.1 Add the CHANGELOG bullet under `[Unreleased]`
- [ ] 3.2 Run `pixi run verify` and confirm it is green
