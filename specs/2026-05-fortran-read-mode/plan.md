# Slice A-1 plan: Read-mode create-or-resolve-and-validate

## Phase 1 — API reshape: create-or-resolve-and-validate

**Scope.** Switch the four directives that pp_ser emits outside
SELECT-CASE to a single create-or-resolve-and-validate shape.

**Steps.**

1. `fs_register_field`: on write mode, create as today; on read mode,
   resolve the `/_fields/<name>` registry entry and validate the
   runtime args (type, dims, halos) match. Mismatch → `error stop`
   with a clear message naming the offending field and field property.
2. `fs_create_savepoint`: on read mode, resolve the existing savepoint
   group (`sp_NNNNNN` index plus `name` attribute disambiguation per
   `storage_mapping.md` §5) and validate the runtime `name` argument
   against the group's `name` attribute.
3. `fs_add_savepoint_metainfo` / `fs_add_serializer_metainfo` (all
   scalar overloads): on read mode, validate that the existing
   attribute's value **and** `__preserf_type_id` match the runtime
   arguments.
4. Decide and document the abort-message style for all four (file +
   group + attribute path; mismatch description). Reuse the same
   helper if practical.

**Tests.**

- New native Fortran scenario in `tests-fortran/unit/m_preserf/` that
  writes a store, closes it, opens read-only, and replays the same
  REGISTER / SAVEPOINT / METAINFO calls. Asserts that no `nf90_def_*`
  was attempted (smoke via run-without-crash + read-only file mode).
- Negative-test scenarios for each of register-mismatch (dtype, dims,
  halos), savepoint-name-mismatch, metainfo-value-mismatch,
  metainfo-typeid-mismatch — assert the abort message.

**Exit criteria.** Read-mode round-trip + four negative cases pass on
ctest; existing write-mode test still passes.

## Phase 2 — Reference-store grpid resolution

**Scope.** Resolve the `ppser_serializer` vs `ppser_serializer_ref`
savepoint-grpid mismatch — currently `ppser_savepoint` lives on
`ppser_serializer` so an explicit reference store would validate
against one file and read from another.

**Steps.**

1. Decide between two approaches in design notes (and a brief comment
   in the source):
   - (a) Savepoints carry per-serializer grpids — more state, less I/O.
   - (b) `fs_read_field` re-resolves the savepoint under `s` before
     reading — less state, more I/O.
2. Implement the chosen approach.

**Tests.**

- Native scenario that opens a primary store and an explicit
  `directory_ref` / `prefix_ref` reference store, replays a savepoint,
  reads against the reference store, and asserts the data came from
  the reference file (not the primary).

**Exit criteria.** Explicit-reference scenario passes; same-store
round-trip from Phase 1 still passes.

## Phase 3 — Outstanding tech-debt cleanup

**Scope.** Two PR #4 review notes that naturally fold into A-1.

**Steps.**

1. Add an explicit negative test for read-side
   `require_variable_xtype` rejection (PR #4 review note).
2. Add a `next_sp_index` increment / `sp_000001` naming round-trip in
   the test scenarios above (PR #4 review note — currently the native
   test only creates one enabled savepoint).
3. Optionally extend the disabled-savepoint round-trip to check
   `owner_ncid` alongside `grpid` and `idx` (PR #4 review note).

**Tests.** Covered by the additions above.

**Exit criteria.** `pixi run test-fortran` green; all PR #4 advisory
notes that fold into A-1 are either tested or explicitly closed in
the PR description.
