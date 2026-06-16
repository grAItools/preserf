# Differential test: preserf vs upstream `pp_ser`

## Why

preserf is a Python re-implementation ("port") of the upstream Serialbox
`pp_ser.py` preprocessor. Both expand `!$SER` directives in Fortran into calls
against the **same** Serialbox runtime API (`fs_write_field`, `fs_read_field`,
`fs_create_savepoint`, `ppser_*`, …).

Today preserf's expansion is validated only against **hand-written** expected
strings in `tests/unit_tests/test_preprocessor.py`. If a hand-written
expectation encodes a misunderstanding of the directive semantics, the test
agrees with the bug. The repo already vendors the real upstream preprocessor at
`vendor/pp_ser.py` (Serialbox 2.6.3) for exactly this reason — per
`vendor/README.md`, it is "kept so the preserf preprocessor can be validated
against the upstream behaviour." Nothing yet uses it.

This is the follow-up to PR #106's golden-fixture work: that pinned the
test-support Serialbox _dump reader_ against external ground truth; this pins
the **preprocessor itself** — preserf's actual product — against the reference
implementation it ports.

## What

A differential test that, for a corpus of `!$SER` inputs, runs **both** preserf
(in-process) and the vendored upstream `pp_ser` (in-process) and compares the
**normalized sequence of generated runtime calls** (`call fs_*` / `call
ppser_*`), ignoring incidental formatting (comments, `#ifdef` wrapper,
`USE`-block ordering, `! file: lineno:` annotations, whitespace/continuations).

The comparison is of _serialization intent_ — which fields are written/read, at
which savepoint, with which arguments, in what order — not byte-for-byte text.
That is the axis where real bugs live (e.g. issue #103: subscript arithmetic
wrongly classified as write-only and silently dropped on read).

### Two tiers

1. **Agreement.** Directives where preserf must match upstream exactly:
   `INIT`, `SAVEPOINT` (+ metainfo), `MODE`, `DATA` for non-diverging values
   (plain scalars, full-slice subscripts, top-level computed/write-only values
   like `a+b` / `merge(...)`), and `CLEANUP`. Strict equality of the normalized
   call sequence.

2. **Intentional divergence (pinned).** preserf deliberately _improves_ on
   upstream for indexed values whose subscripts contain arithmetic
   (`arr(i-1)`, `arr(i+1)`, `arr(2*i)`, `a(i)%b(j-1)`): preserf reads them back,
   upstream `pp_ser` misclassifies them as computed and drops the read. The test
   asserts this _specific_ difference so the divergence stays **intentional and
   visible** — it fails if preserf regresses to dropping the read (re-breaking
   #103) **or** if upstream's vendored behaviour ever changes.

## Acceptance criteria

- A new unit test (no Fortran toolchain, no network, no new dependency) that:
  - passes the agreement corpus by exact normalized-call equality;
  - pins each subscript-arithmetic divergence (preserf reads back, upstream does
    not, both write);
  - imports the vendored `pp_ser` by path (it is not a package and must never be
    imported into shipped code — it stays test-only, matching `vendor/README.md`).
- `pixi run verify` stays green.
- No change to preserf's `src/` behaviour — this is a characterization/diff test
  only.

## Non-goals

- No runtime round-trip (compiling/running the generated Fortran against the
  real Serialbox library) — out of scope and toolchain-heavy.
- No new `serialbox4py` / pip dependency: the vendored `pp_ser.py` is pure
  stdlib Python, so the test is fully hermetic.
- Not exhaustive directive coverage; a representative corpus that exercises the
  core directives and the known classification boundary.

## Open item for a maintainer (flagged, not changed here)

`vendor/README.md` records `pp_ser.py`'s license as **GPL**, but the vendored
file's own header (Serialbox 2.6.3) states **BSD**. Test-only, non-distributed
use is fine either way, so this PR does not touch the license note — but the
discrepancy should be reconciled separately.
