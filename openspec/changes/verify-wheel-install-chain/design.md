# Design

## Context

The external-consumer and `find_package` tests build a real downstream
project, but they resolve `preserf` from the editable in-tree install
(`pixi.toml:11-12` puts the repo checkout on PATH), so
`get_cmake_helper()` returns a worktree path — the wheel-content test
proves the files ship and the consumer test proves the recipe works, but
no test proves both for the same artifact. The `twine check` test was
written as best-effort with a skipif that never fires because twine is in
no environment. The expected-files slice omits exactly the two files a
typing-aware and doc-reading consumer cares about.

## Goals / Non-Goals

**Goals:**

- The wheel→install→consume chain is executed, not inferred: a clean venv,
  a `pip install` of the built wheel, and the existing consumer CMake
  recipe driven from that install's `preserf --cmake-helper`.
- The metadata gates run by default in the development environment.
- The expected-files slice covers the typing and docs payload.

**Non-Goals:**

- Release/publish automation (no PyPI workflow until 0.2.0).
- New CI lanes for linux-aarch64 or NVHPC (documented gaps, out of scope).
- Runtime portability work; the POSIX-only prerequisite is documented
  rather than fixed.

## Decisions

- Sequencing: this change lands after `restore-fast-test-slice`, which
  owns the `packaging` marker on the same test file
  (`test_packaging_distribution.py`); the two share the marker
  configuration and must not fight over it.
- Reuse the existing `_CONSUMER_CMAKE` recipe and `_build_wheel()` helper;
  the new test installs into a venv under `tmp_path` and asserts the
  consumer build succeeds against that install only.
- Add `twine>=6` to the dev feature's pypi-dependencies (test-scoped, no
  runtime dependency, so no ADR is required) and let the existing skipif
  become always-false.
- Assert `METADATA`'s `Version:` equals `preserf.__version__` in the same
  packaging test, closing the spec's version-bump scenario with an
  assertion instead of a comment.
- Keep the "OS Independent" classifier (it describes the Python artifact)
  but state the POSIX-only Fortran runtime prerequisite in the root
  README's build section, and rewrite the shipped runtime README's links
  as absolute repository URLs.

## Risks / Trade-offs

- Venv creation and a pip install add roughly a minute to the consumer
  lane; the `consumer` marker keeps it out of the fast slice.
- The venv-based test depends on network access for pip; mitigated by
  `--no-index` with a `find-links` pointing at the locally built wheel
  where CI requires hermetic builds.
