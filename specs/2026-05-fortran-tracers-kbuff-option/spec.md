# Slice C: Tracers, k-buffer, OPTION

## Problem

`!$SER TRACER`, `!$SER DATA_KBUFF`, and `!$SER OPTION` would fail to
link against the v0.1 Fortran helper. The corresponding helper API
(`fs_RegisterAllTracers`, `ppser_write_tracer_*`, `fs_write_kbuff`,
`fs_Option`) does not exist.

## Goal

pp_ser-generated source using `!$SER REGISTERTRACERS`, `!$SER TRACER`,
`!$SER DATA_KBUFF`, or `!$SER OPTION` directives links, runs, and
produces a store that round-trips through the Python reader.

## Non-goals

- Defining the on-disk tracer-descriptor layout — that decision is
  the predecessor Slice C-0, which lands as
  `docs/adr/0003-tracer-storage.md`. Slice C consumes the layout the
  ADR ratifies.
- Read-mode validation of the new helpers — Slice A-1 establishes the
  resolve-and-validate pattern this slice will follow.
- Type-coverage matrix for tracer fields beyond what Slice B
  establishes for plain fields.

## Dependencies

**Depends on Slice C-0** (tracer-storage ADR). The ADR must be
accepted as `docs/adr/0003-tracer-storage.md` and
`docs/references/storage_mapping.md` updated to reflect it, _before_
Slice C opens. Without that, Slice C would have to relitigate the
layout in its implementation PR.

## Success criteria

- `fs_RegisterAllTracers` (from `!$SER REGISTERTRACERS`) writes
  tracer descriptors at the layout ratified by ADR 0003.
- Tracer write API: `ppser_write_tracer_by_name`,
  `ppser_write_tracer_by_idx`, `ppser_write_tracer_all` (from
  `!$SER TRACER`, per
  `docs/references/directives_specification.md` §§3.11 / 3.14) all
  exist and round-trip.
- `fs_write_kbuff` implements `!$SER DATA_KBUFF` with k-buffer flush
  semantics re-derived from `vendor/pp_ser.py`.
- `fs_Option` accepts the OPTION keyword-argument surface pp_ser
  actually emits (e.g. `call fs_Option(verbosity=1)`). The surface
  is enumerated in this spec or the implementation PR before code
  lands.
- Cross-language coverage in
  `tests/integration_tests/test_fortran_wire_compat.py` (or a
  sibling test program) for at least one TRACER, one DATA_KBUFF,
  and one OPTION scenario.
