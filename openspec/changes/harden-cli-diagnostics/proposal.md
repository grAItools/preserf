# Proposal

## Why

The CLI's failure modes are inconsistent with its own
one-line-diagnostic contract: an `OSError` raised while walking an
input directory escapes `_collect`'s `ValueError`-only handler as a
raw traceback (`src/preserf/cli.py:265-268`); several source files
preprocessed with neither `-o` nor `-d` are silently concatenated to
stdout with duplicated `#define ACC_PREFIX` headers; explicit
non-Fortran file arguments pass through without comment although the
suffix filter exists; and the `--version` callback prints through a
rich `Console` while the path callbacks deliberately use bare `print`
for clean command substitution.

## What Changes

- Catch `OSError` alongside `ValueError` around directory collection and route it through the one-line failure path
- Reject multi-source runs that lack an explicit output destination instead of concatenating
- Warn when an explicitly named file argument does not look like Fortran source
- Unify the callbacks on bare `print`; drop the dead half of the success-bookkeeping condition; hoist the root `is_dir` stat out of the per-file loop

## Out of Scope

- Preprocessor engine changes, `--output-dir` semantics, and the recursive mirroring rules
- Performance work beyond the root-stat hoist

## Capabilities

### Modified Capabilities

- `cli`: error reporting gains graceful operating-system failure handling; a new input-validation requirement pins single-destination semantics and suffix checking

## Impact

`src/preserf/cli.py`, `tests/unit_tests/test_cli.py`, CHANGELOG.
