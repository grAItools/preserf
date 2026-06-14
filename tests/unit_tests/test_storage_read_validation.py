"""Negative tests for ``read_dump()``'s validation branches.

``tests/_support/storage.py`` ``read_dump()`` is the trusted oracle for the
round-trip and cross-language wire-compat tests: those tests assert that what
the Fortran helper (or the Python writer) produced reads back correctly, so an
*incorrect* guard in ``read_dump()`` — one that passes when it should fail, or
fails when it should pass — would silently weaken every test that leans on it.

These tests pin each hand-written validation branch by building a valid store
with the shared ``_make_dump`` / ``write_dump`` helpers, corrupting exactly one
invariant in place, and asserting ``read_dump()`` raises with a
branch-specific message. They use the ``netcdf4`` backend because a single
``.nc`` file can be reopened in append mode (``nc.Dataset(url, "a")``) and
mutated attribute-by-attribute; the validation logic is backend-independent.

All branches are reached and confirmed raising; none are unreachable.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import netCDF4 as nc
import numpy as np
import pytest

if TYPE_CHECKING:
    from pathlib import Path

from tests._support.storage import read_dump, write_dump

from .test_storage_round_trip import _make_dump


def _write_valid_store(tmp_path: Path) -> str:
    """Build a valid preserf store on the netcdf4 backend and return its URL.

    ``_make_dump`` registers field ``u`` with three savepoints carrying field
    ids 0, 1, 2 — a dense set — which the dense-id and consistency branches
    rely on as their starting point.
    """
    return write_dump(_make_dump(), tmp_path / "store", backend="netcdf4")


def test_read_dump_rejects_missing_schema_version(tmp_path: Path) -> None:
    """A store with no ``_preserf_schema_version`` attribute is rejected."""
    url = _write_valid_store(tmp_path)
    root = nc.Dataset(url, "a")
    try:
        root.delncattr("_preserf_schema_version")
    finally:
        root.close()
    with pytest.raises(ValueError, match="missing required '_preserf_schema_version'"):
        read_dump(url)


def test_read_dump_rejects_bad_schema_version(tmp_path: Path) -> None:
    """A schema version other than the one this build supports is rejected."""
    url = _write_valid_store(tmp_path)
    root = nc.Dataset(url, "a")
    try:
        root.setncattr("_preserf_schema_version", np.int32(999))
    finally:
        root.close()
    with pytest.raises(ValueError, match="unsupported preserf schema version 999"):
        read_dump(url)


def test_read_dump_rejects_missing_fields_group(tmp_path: Path) -> None:
    """A store missing the ``/_fields`` registry group is rejected.

    netCDF4 cannot delete a group, so the group is renamed out of the way —
    the reader keys on the literal name ``_fields``.
    """
    url = _write_valid_store(tmp_path)
    root = nc.Dataset(url, "a")
    try:
        root.renameGroup("_fields", "_fields_moved")
    finally:
        root.close()
    with pytest.raises(ValueError, match="missing required '/_fields' group"):
        read_dump(url)


def test_read_dump_rejects_missing_savepoints_group(tmp_path: Path) -> None:
    """A store missing the ``/savepoints`` group is rejected."""
    url = _write_valid_store(tmp_path)
    root = nc.Dataset(url, "a")
    try:
        root.renameGroup("savepoints", "savepoints_moved")
    finally:
        root.close()
    with pytest.raises(ValueError, match="missing required '/savepoints' group"):
        read_dump(url)


def test_read_dump_rejects_odd_length_field_ids(tmp_path: Path) -> None:
    """``_preserf_field_ids`` must be flat (fieldname, id) pairs."""
    url = _write_valid_store(tmp_path)
    root = nc.Dataset(url, "a")
    try:
        grp = root.groups["savepoints"].groups["sp_000000"]
        grp.setncattr("_preserf_field_ids", ["u", "0", "dangling"])
    finally:
        root.close()
    with pytest.raises(ValueError, match="_preserf_field_ids has odd length 3"):
        read_dump(url)


def test_read_dump_rejects_duplicate_field_ids(tmp_path: Path) -> None:
    """A field appearing twice in ``_preserf_field_ids`` is rejected."""
    url = _write_valid_store(tmp_path)
    root = nc.Dataset(url, "a")
    try:
        grp = root.groups["savepoints"].groups["sp_000000"]
        grp.setncattr("_preserf_field_ids", ["u", "0", "u", "0"])
    finally:
        root.close()
    with pytest.raises(ValueError, match="duplicate entry for field 'u'"):
        read_dump(url)


def test_read_dump_rejects_inconsistent_field_ids(tmp_path: Path) -> None:
    """``_preserf_field_ids`` must list exactly the savepoint's field variables.

    Here it names a field (``ghost``) that has no variable in the savepoint
    group, so the mapped set diverges from the variable set.
    """
    url = _write_valid_store(tmp_path)
    root = nc.Dataset(url, "a")
    try:
        grp = root.groups["savepoints"].groups["sp_000000"]
        # sp_000000 in _make_dump carries u, nlevels, scalar_flag.
        grp.setncattr(
            "_preserf_field_ids",
            ["u", "0", "nlevels", "0", "scalar_flag", "0", "ghost", "0"],
        )
    finally:
        root.close()
    with pytest.raises(ValueError, match=r"_preserf_field_ids is.*inconsistent"):
        read_dump(url)


def test_read_dump_rejects_non_dense_field_ids(tmp_path: Path) -> None:
    """A field's reconstructed ids must be the dense range ``0..N-1``.

    ``u`` is written with ids {0, 1, 2}; rewriting one savepoint's id to 5
    yields the sparse set {0, 2, 5}, which Serialbox's BinaryArchive never
    produces, so the store is refused.
    """
    url = _write_valid_store(tmp_path)
    root = nc.Dataset(url, "a")
    try:
        # sp_000001 maps u -> id 1; bump it to 5 to break density.
        grp = root.groups["savepoints"].groups["sp_000001"]
        grp.setncattr("_preserf_field_ids", ["u", "5", "nlevels", "1"])
    finally:
        root.close()
    with pytest.raises(ValueError, match="non-dense fieldIDs"):
        read_dump(url)


def test_read_dump_rejects_savepoint_variable_absent_from_registries(
    tmp_path: Path,
) -> None:
    """A savepoint variable must resolve to a ``/_fields`` or ``/_tracers``
    entry.

    A ``ghost`` variable is added to a savepoint and listed in
    ``_preserf_field_ids`` (so the consistency check passes), but no matching
    registry entry exists, so the store is internally inconsistent.
    """
    url = _write_valid_store(tmp_path)
    root = nc.Dataset(url, "a")
    try:
        grp = root.groups["savepoints"].groups["sp_000000"]
        grp.createDimension("ghost_dim0", 2)
        var = grp.createVariable("ghost", "f8", ("ghost_dim0",))
        var[...] = np.array([9.0, 9.0])
        # sp_000000 carries u, nlevels, scalar_flag (+ the new ghost).
        grp.setncattr(
            "_preserf_field_ids",
            ["u", "0", "nlevels", "0", "scalar_flag", "0", "ghost", "0"],
        )
    finally:
        root.close()
    with pytest.raises(
        ValueError, match=r"no matching entry exists under.*'/_fields' or '/_tracers'"
    ):
        read_dump(url)
