# Design

## Context

All three bugs were reproduced empirically by direct `Preprocessor`
invocation during the review, and they interact: fixing the intent regex
alone still leaves directive lines exposed to the scanner, and fixing the
dispatch order alone still misses `dimension(:)` declarations, so the
fixes share regression tests and land together. The three sites are the
standalone-subprogram lookahead (`src/preserf/preprocessor.py:448-458`),
the intent regex (`preprocessor.py:146-148`), and the scanner ordering
with its `::` gate (`preprocessor.py:403`, `:486`); the intent-removal
recorder sits at `preprocessor.py:1057-1062`. The engine is a typed port
of Serialbox's `pp_ser.py`; two of the behaviors (comment tolerance
between continuations, attribute-order-independent declarations) are
legal free-form Fortran that the reference also mishandles or leaves
unpinned, so the fixes intentionally diverge from the reference where
the reference is wrong or silent.

## Goals / Non-Goals

**Goals:**

- Every legal free-form input that preprocesses correctly today continues
  to; the three miscompilations are gone.
- Regression tests pin comment/blank tolerance, attribute order, comment
  immunity, and the computed-value exemption so the fixes cannot silently
  regress.

**Non-Goals:**

- Fixed-form sources and tab-indented directives (matching literal spaces
  only is consistent with the reference `pp_ser`).
- Merging the per-line regex scans, collapsing the two-pass model, or
  memoizing per-file analysis (explicitly preserved per the review).
- The `_scan_subprogram` continuation-gathering string concatenation is
  theoretically quadratic in continuation count but bounded by realistic
  Fortran line structure; not restructured here.

## Decisions

- Lookahead consumes only lines matching the existing `&`-continuation
  pattern; any other line (comment, blank) ends the header run and flows
  through the normal per-line dispatch untouched.
- The intent span becomes paren-aware (colons inside `dimension(:)` and
  kind specs no longer break the match), verified against both attribute
  orders.
- Directive recognition runs before intent scanning in the per-line
  dispatch, and the `::` gate strips trailing comments first so comment
  text can never satisfy it.
- Computed (write-only) DATA values are exempt from intent-removal
  recording: the classifier already marks them write-only, so recording
  them needlessly strips `INTENT(IN)` in the serialize branch of inputs
  that compile either way — the exemption keeps the two spellings of a
  computed expression treated identically.
- The inline `re.sub(r"!.*")` patterns in the touched regions are hoisted
  to module constants beside the existing regex inventory.

## Risks / Trade-offs

- The paren-aware span is harder to read than the original; mitigated with
  table-driven tests covering both attribute orders and kind specs.
- Reordering the dispatch changes behavior for lines that are both
  directive-shaped and declaration-shaped; the differential corpus against
  the reference `pp_ser` guards against unintended divergence.
