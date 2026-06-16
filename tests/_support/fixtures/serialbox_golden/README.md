# Golden Serialbox dump (external ground truth)

This directory holds a small **real** Serialbox `BinaryArchive` dump,
produced by upstream Serialbox (not by preserf's own reimplementation), plus
the script that generated it. It is the external ground truth referenced by
issue [#68](https://github.com/grAItools/preserf/issues/68):
`tests/_support/serialbox.py` is a hand re-implementation of the Serialbox
on-disk format, and before this fixture existed it was validated _only_ by a
self-round-trip — so a writer + reader that agreed on a wrong interpretation
of the format would still pass.

`tests/unit_tests/test_serialbox_golden.py::test_serialbox_reader_decodes_golden_dump`
asserts the reimplementation decodes this dump to the exact values upstream
Serialbox itself reads back.

## What it covers

- Two savepoints sharing the name `step`, distinguished by metainfo.
- Mixed dtypes / ranks: `u` (Float64, rank 3), `nlevels` (Int32, rank 1),
  `ftol` (Float32, rank 1).
- A field written at multiple savepoints (`u`, snapshots 0 and 1).
- Global metainfo of mixed scalar types plus an `ArrayOfString` entry
  (`tags`).

## What it caught

The 3-D field `u` exposed that Serialbox's `BinaryArchive` stores array
payloads in **column-major (Fortran) order** while `MetaData`'s `dims` lists
the extents in declaration order. The reimplementation reshaped the raw
`.dat` blob in C-order, which transposes rank >= 2 fields. Rank 0/1 happen
to coincide, so the symmetric self-round-trip never noticed. The fix
(`order="F"` on both the read reshape and the write `tobytes`) was verified
both ways against `serialbox4py`: it now decodes real dumps _and_ writes
dumps real Serialbox reads back correctly.

## Provenance

| Item     | Value                                                                                              |
| -------- | -------------------------------------------------------------------------------------------------- |
| Producer | `serialbox4py` (GridTools/serialbox) — upstream C++ runtime via its Python bindings                |
| Version  | Serialbox **2.6.3** (`serialbox4py==2.6.3` from PyPI; `serialbox_version` in the JSON reads `263`) |
| Archive  | `Binary` (BinaryArchive), `hash_algorithm = SHA256`                                                |

## Regenerating

`serialbox4py` is a heavy prebuilt-binary, non-preserf dependency and is
deliberately **not** in `pixi.toml`; the dump is committed so the test suite
needs no network or extra toolchain. To regenerate (e.g. to bump the
Serialbox version) in a throwaway environment:

```sh
pip install serialbox4py==2.6.3 numpy
python tests/_support/fixtures/serialbox_golden/generate_golden.py \
    tests/_support/fixtures/serialbox_golden
```

Re-run `pixi run test-py-unit` afterwards and update the version notes here
and in `generate_golden.py` if the on-disk shape changed.

## Files

| File                          | Description                                                               |
| ----------------------------- | ------------------------------------------------------------------------- |
| `MetaData-golden.json`        | Serializer metadata: `field_map`, `global_meta_info`, `savepoint_vector`. |
| `ArchiveMetaData-golden.json` | BinaryArchive `fields_table` (per-snapshot offsets + SHA256 checksums).   |
| `golden_u.dat`                | Raw payload for field `u` (2 snapshots x 24 f64 = 384 bytes).             |
| `golden_nlevels.dat`          | Raw payload for field `nlevels` (3 i32 = 12 bytes).                       |
| `golden_ftol.dat`             | Raw payload for field `ftol` (2 f32 = 8 bytes).                           |
| `generate_golden.py`          | The script that produced the dump above.                                  |
