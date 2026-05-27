# Slice C plan: Tracers, k-buffer, OPTION

## Phase 0 — Wait for Slice C-0 (tracer-storage ADR)

This slice cannot open until the tracer-descriptor layout is ratified
in `docs/adr/0003-tracer-storage.md` and reflected in
`docs/references/storage_mapping.md`. C-0 is docs-only (an ADR plus a
storage-mapping update), but separating the layout decision from the
implementation PR keeps schema review and code review on independent
change-sets.

## Phase 1 — Tracers (`!$SER REGISTERTRACERS` + `!$SER TRACER`)

**Scope.** Add `fs_RegisterAllTracers` and the three tracer write
entry points pp_ser emits.

**Steps.**

1. `fs_RegisterAllTracers` writes the tracer descriptor set at the
   ADR-ratified location (candidate from the ADR: a `/_tracers`
   sibling of `/_fields`).
2. `ppser_write_tracer_by_name(name, data, savepoint)` —
   `!$SER TRACER` with explicit name.
3. `ppser_write_tracer_by_idx(idx, data, savepoint)` —
   `!$SER TRACER` with index.
4. `ppser_write_tracer_all(data, savepoint)` — `!$SER TRACER all`.

**Tests.**

- Cross-language test: Fortran writes a tracer set through each of
  the three entry points; Python reads back and asserts that both
  descriptors and data round-trip.

**Exit criteria.** All three entry points round-trip; the ADR's
layout is what's actually on disk.

## Phase 2 — DATA_KBUFF (`fs_write_kbuff`)

**Scope.** Implement the k-buffer write path with the same flush
semantics as `vendor/pp_ser.py`.

**Steps.**

1. Re-derive the k-buffer flush semantics from `vendor/pp_ser.py`
   (the canonical Python source) and document in a source comment.
2. Implement `fs_write_kbuff` accumulating into the buffer and
   flushing at the right boundary.

**Tests.**

- Cross-language test: Fortran writes a multi-step DATA_KBUFF
  sequence; Python reads the resulting store and asserts the buffered
  field matches the expected accumulation.

**Exit criteria.** DATA_KBUFF semantics match `vendor/pp_ser.py`'s
reference behaviour.

## Phase 3 — OPTION (`fs_Option`)

**Scope.** Implement `fs_Option` for the keyword-argument surface
pp_ser actually emits.

**Steps.**

1. Enumerate the supported `fs_Option` optional-argument surface
   (e.g. `verbosity`, plus whatever pp_ser actually emits across the
   reference test corpus). Decide whether to fix the helper's surface
   or change the pp_ser port's emission shape to a `(name, value)`
   pair. Pick one and update either the helper or the port — not
   both.
2. Decide how OPTION entries land in the store (likely as serializer
   metainfo with a `_option_` prefix, but enumerate in this PR).

**Tests.**

- Cross-language test: Fortran writes via `fs_Option(verbosity=1)`;
  Python reads the option from the expected location and asserts the
  value.

**Exit criteria.** All emitted OPTION calls compile, run, and the
options round-trip through the store.
