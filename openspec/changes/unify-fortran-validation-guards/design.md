# Design

## Context

The two same-named `require_fits_int32` guards diverged deliberately
(each module keeps a private copy; the `m_preserf` copy documented that
its callers pre-reject negatives), but `fs_Option` broke that contract
without anyone noticing — the exact silent-wrap class `dev/style.md`
names as the anti-pattern. The k-buffer and field read paths validate
differently (`kbuff_load_full` checks the on-disk variable only against
the k-buffer table's own shape), and `fs_write_field` lacks the friendly
read-only abort its sibling `fs_register_field` has. The stale
README/e2e claims were verified against native scenarios that do cover
explicit refs.

## Goals / Non-Goals

**Goals:**

- Both private guards check both bounds; no silent wrap path remains.
- The two read paths are validation-equivalent: registry consulted
  before load, friendly aborts on handle-state violations.
- Docs state actual coverage.

**Non-Goals:**

- Append mode and string-array metainfo (tracked in their own changes).
- Wire-format changes, new public API, thread-safety work, and the
  non-ASCII path hardening in the nczarr URL builder.
- A shared guard module: the per-module copies stay (each module needs a
  private copy for separate compilation), and the both-bounds fix
  removes the actual hazard without new coupling.

## Decisions

- Keep a private copy per module (the deliberate duplication) but make
  both check both bounds, so no future caller can inherit the wrap
  class.
- The k-buffer read path fetches registry dims before `kbuff_load_full`,
  mirroring `preserf_read_field.inc`.
- `fs_Option`'s existing `ncid`/`writable` gate already covers the
  uninitialized case; no additional open-state guard is added there.
- Doc fixes: the README bullet points at the native `read-ref`
  scenarios; the e2e header comment states that the omission is a
  choice, not a linking constraint.

## Risks / Trade-offs

- Stricter validation can reject stores that previously passed the kbuff
  path (registry/variable disagreement); those stores were already
  inconsistent, so rejecting loudly is the correct behavior and is
  CHANGELOG-noted.
- In-range negative option values still pass (they do not wrap); the
  guard's contract is range-safety, not semantic validation.
