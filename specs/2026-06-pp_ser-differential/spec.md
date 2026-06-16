# Differential test: preserf vs upstream `pp_ser`

## Why

preserf is a Python re-implementation ("port") of the upstream Serialbox
`pp_ser.py` preprocessor. Both expand `!$SER` directives in Fortran into calls
against the **same** Serialbox runtime API (`fs_write_field`, `fs_read_field`,
`fs_create_savepoint`, `ppser_*`, …).

Today preserf's expansion is validated only against **hand-written** expected
strings in `tests/unit_tests/test_preprocessor.py`. If a hand-written
expectation encodes a misunderstanding of the directive semantics, the test
agrees with the bug. The real upstream preprocessor is published in the
`serialbox4py` distribution (it ships `pp_ser.py` inside the `serialbox`
package), so we can run it directly as external ground truth — see
[ADR 0006](../../docs/adr/0006-ppser-differential-dependency.md) for why we
depend on the published package rather than vendoring a pinned copy.

This is the follow-up to PR #106's golden-fixture work: that pinned the
test-support Serialbox _dump reader_ against external ground truth; this pins
the **preprocessor itself** — preserf's actual product — against the reference
implementation it ports.

## What

A differential test that, for a corpus of `!$SER` inputs, runs **both** preserf
(in-process) and the upstream `pp_ser` from `serialbox4py` (in-process) and compares the
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
   #103) **or** if upstream's published behaviour ever changes.

## Acceptance criteria

- A new unit test (no Fortran toolchain, no network at test time) that:
  - passes the agreement corpus by exact normalized-call equality;
  - pins each subscript-arithmetic divergence (preserf reads back, upstream does
    not, both write);
  - loads the upstream `pp_ser` from the installed `serialbox4py` package
    (test-only dependency) without importing the native Serialbox runtime.
- `pixi run verify` stays green.
- No change to preserf's `src/` behaviour — this is a characterization/diff test
  only.

## Non-goals

- No runtime round-trip (compiling/running the generated Fortran against the
  real Serialbox library) — out of scope and toolchain-heavy.
- No bundling of upstream `pp_ser` source in-tree: it comes from the published
  `serialbox4py` package (test/dev only — not a runtime dependency, not shipped
  in preserf's wheel/sdist). See ADR 0006.
- Not exhaustive directive coverage; a representative corpus that exercises the
  core directives and the known classification boundary.
