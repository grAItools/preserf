# Slice C tasks: Tracers, k-buffer, OPTION

Tracks the phased plan in `plan.md` (and the folded-in ADR per
`/root/.claude/plans/...`). Tick as each lands.

## Phase 0 — ADR 0003 + storage mapping

- [x] `docs/adr/0003-tracer-storage.md` (Accepted): `/_tracers` layout,
      built-in tracer registry, OPTION surface, k-buffer flush, timelevel
      = attribute (single snapshot, last-wins)
- [x] `docs/references/storage_mapping.md`: `/_tracers` (§4a), OPTION
      values (§4b), layout diagram, `_preserf_option_*` housekeeping row

## Phase 1 — Tracers (`REGISTERTRACERS` + `TRACER`)

- [x] Tracer registry state + reset in `utils_preserf.f90`; `/_tracers`
      skeleton group (create + lenient resolve)
- [x] `ppser_register_tracer` (real64 ranks 1–4) via CPP template
- [x] `fs_RegisterAllTracers` — write `/_tracers` descriptors (write mode),
      resolve-and-validate (read mode)
- [x] `ppser_write_tracer_by_name` / `_by_idx` (single + range) / `_all`
      (with stype filter); optional `timelevel` attribute
- [x] Python reader: surface `/_tracers` + per-savepoint tracer data +
      timelevel in `SerialboxDump` (`storage.py`, `serialbox.py`)
- [x] Native `tracers` + `tracers-roundtrip` ctest scenarios
- [x] Cross-language `test_fortran_writes_tracers_python_reads`
- [x] Re-export shim note (`m_serialize.f90`); CHANGELOG entry

## Phase 2 — DATA_KBUFF (`fs_write_kbuff`)

- [x] k-buffer table state + reset in `utils_preserf.f90`
- [x] `fs_write_kbuff` (real64 slice ranks 1-3) via CPP template:
      accumulate per-level, flush at `k == k_size` through `fs_write_field`
- [x] Cross-language multi-step DATA_KBUFF test (`kbuff` scenario +
      `test_fortran_writes_kbuff_python_reads`); native `kbuff` ctest

## Phase 3 — OPTION (`fs_Option`)

- [ ] `fs_Option(verbosity)` + module verbosity state +
      `_preserf_option_verbosity` root attribute
- [ ] Tighten `_ser_option` to reject non-`verbosity` keys + unit test
- [ ] Cross-language OPTION round-trip test

## Close-out (after Phase 3)

- [ ] `specs/README.md` progress table: C-0 + C → shipped
- [ ] Remove any remaining "not yet implemented" notes / `error stop` stubs
