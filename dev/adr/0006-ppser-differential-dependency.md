# 6. Use serialbox4py (test-only) for the pp_ser differential test

## Status

Accepted

## Context

preserf is a Python re-implementation ("port") of the upstream Serialbox
`pp_ser.py` preprocessor. To keep the port honest, the differential test in
`tests/unit_tests/test_pp_ser_differential.py` runs the real upstream `pp_ser`
on the same `!$SER` corpus and compares the normalized sequence of generated
runtime calls (see `specs/2026-06-pp_ser-differential/`).

That test needs a copy of upstream `pp_ser` to run. Two options were on the
table:

1. **Vendor a pinned `pp_ser.py` in-tree** (`vendor/pp_ser.py`). This is how the
   first cut of the differential test worked. It is fully offline, but it means
   hand-maintaining a frozen copy of a third-party script: it drifts from
   upstream, needs manual refresh, and carries its own license bookkeeping
   (`vendor/README.md` recorded the license as GPL while the file's own header
   states BSD — a discrepancy nobody could confidently resolve).
2. **Depend on the published `serialbox4py` distribution** and load `pp_ser`
   from it. `serialbox4py` ships `pp_ser.py` inside the `serialbox` package at
   `serialbox/python/pp_ser/pp_ser.py`. The script itself is pure stdlib.

The `serialbox4py` wheels cover all platforms preserf builds on
(`manylinux` x86-64 / aarch64, `macosx` arm64), and `serialbox4py` is already
used elsewhere in the test suite as the source of the golden Serialbox dump
fixture (issue #68), so it is not a new project-wide dependency in spirit.

## Decision

Depend on **`serialbox4py`** as a **test-only / dev** dependency (declared under
`[feature.dev.pypi-dependencies]` in `pixi.toml`) and load upstream `pp_ser`
from the installed package instead of vendoring a copy. The vendored
`vendor/pp_ser.py` (and `vendor/README.md`) are removed.

Loading detail: `pp_ser.py` is not an importable submodule (its directory has no
`__init__.py`, and importing the top-level `serialbox` package pulls in the
native Serialbox runtime, which the test does not need). The reference harness
(`tests/_support/ppser_reference.py`) therefore resolves the `serialbox` package
location with `importlib.util.find_spec("serialbox")` — which does _not_ execute
`serialbox/__init__.py` — and loads the pure-stdlib `pp_ser.py` by path.

This is **not** a runtime dependency: `serialbox4py` is never imported by
anything under `src/`, and is not part of preserf's wheel/sdist.

## Consequences

- The differential test tracks the **published** upstream `pp_ser` release
  rather than a frozen snapshot — it picks up upstream fixes/changes on the next
  `pixi` solve. If upstream behaviour changes, the agreement/divergence
  assertions surface it (by design), prompting a deliberate update.
- No more hand-maintained vendored copy and no GPL/BSD license note to
  reconcile; the `vendor/` directory is retired.
- The test now requires `serialbox4py` to be installed in the `dev`
  environment. It is resolved/locked by `pixi`; the test runs offline once the
  environment is solved. CI and contributors get it automatically via
  `pixi install`. A bare `default`-environment run without the dev feature will
  not collect this test (it lives under `dev`, like the rest of the suite).
- Pinning is delegated to `pixi.lock` (floor `>=2.6.3` in `pixi.toml`); a
  reproducible exact version is recorded in the lockfile.
