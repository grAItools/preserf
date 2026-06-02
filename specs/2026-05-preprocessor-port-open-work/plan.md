# Slice D plan: `ppser_initialize` widening + end-to-end test

## Phase 1 — Widen the `ppser_initialize` signature ✅ done

**Scope.** Add the seven Serialbox-compatible keywords pp_ser passes
through from `!$SER INIT`.

**Steps.**

1. Add `singlefile`, `mpi_rank`, `rprecision`, `rperturb`,
   `realtype`, `archive`, `unique_id` as optional arguments to
   `ppser_initialize` in `src/preserf-fortran/utils_preserf.f90`.
2. Defaults match Serialbox's defaults so existing call sites are
   unaffected.

**Tests.**

- Native scenario: call `ppser_initialize` with each new keyword
  individually (and a default scenario) and assert behaviour /
  recorded state via the existing native-test fixtures.

**Exit criteria.** Signature accepts all seven keywords; existing
write-mode test still passes.

## Phase 2 — Wire the keywords with side-effects ✅ done

**Scope.** Three keywords change behaviour, not just metadata.

**Steps.**

1. **`mpi_rank`**: `preserf_open_serializer` applies a `_rank<n>`
   suffix to the store name per `storage_mapping.md` §9. Without
   this, parallel runs clobber each other's stores. Decide whether
   to do this in `preserf_open_serializer` or in a separate helper —
   document the choice.
2. **`realtype` / `rprecision`**: replace the fixed-constant
   exposure of `ppser_realtype` / `ppser_reallength` with values
   set from the `ppser_initialize` arguments. The constants survive
   as defaults.
3. **`rperturb`**: update `ppser_zrperturb` from the argument.
   Slice A-2's read-perturb path consumes this.

**Tests.**

- Native scenarios:
  - Parallel-rank suffix: open two serializers with `mpi_rank=0` /
    `mpi_rank=1` and assert two distinct files exist.
  - `realtype=real32` REGISTER: register a `real32` field and assert
    the `type_id` attribute on `/_fields/<name>` matches the
    expected single-precision TypeID.
  - `rperturb=<scale>` propagates to `ppser_zrperturb` (a getter test
    is enough until Slice A-2 lands).

**Exit criteria.** All three behaviour-changing keywords produce
observable effects in `tests-fortran/`.

## Phase 3 — Metadata-only keywords ✅ done

Implemented: `preserf_write_init_attrs` in `utils_preserf.f90` records
`_preserf_singlefile` / `_preserf_archive` / `_preserf_unique_id` on the
writable store; `tests/_support/storage.py` reads them onto
`SerialboxDump`; documented in `storage_mapping.md` §3.1. Round-trip
asserted by `tests/integration_tests/test_preprocessor_e2e.py`.

**Scope.** `singlefile`, `archive`, `unique_id` round-trip via root
attributes.

**Steps.**

1. Record each in a root attribute on the netCDF dataset (likely
   `_preserf_singlefile`, `_preserf_archive`, `_preserf_unique_id`
   to match the `_preserf_*` housekeeping namespace).
2. Update `storage_mapping.md` §1 to document the new
   housekeeping attrs.

**Tests.**

- Cross-language: set each via `ppser_initialize`, read back through
  `tests/_support/storage.py`, assert round-trip.

**Exit criteria.** All three values surface in the store and survive
round-trip.

## Phase 4 — End-to-end fixture ✅ done

Implemented: `tests-fortran/e2e/e2e_fixture.f90.in` (preprocessor input)

- `tests-fortran/e2e/CMakeLists.txt` (CMake runs the `preserf` CLI, then
  compiles the generated `.F90` with `-DSERIALIZE` against the helper) +
  `tests/integration_tests/test_preprocessor_e2e.py` (runs the binary,
  reads the store back). Registered as the `preserf_fortran_e2e` ctest.

**Scope.** A representative `!$SER`-annotated Fortran source that
exercises every part of the preprocessor → helper → store pipeline.

**Steps.**

1. Author the fixture source covering at least: `!$SER INIT` with
   non-default keywords, `!$SER REGISTER`, `!$SER SAVEPOINT`,
   `!$SER METAINFO`, `!$SER DATA`. (TRACER / DATA_KBUFF / OPTION
   are Slice C's territory.)
2. Wire a test that runs the preprocessor on the fixture, compiles
   the generated output against the helper, runs the binary, and
   reads back via `tests/_support/storage.py`.

**Tests.** The end-to-end fixture is the test.

**Exit criteria.** End-to-end test passes in CI with
`PRESERF_REQUIRE_FORTRAN=1`. No `error stop` is reached anywhere
along the path.
