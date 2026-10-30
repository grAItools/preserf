"""Perf-smoke fixtures for store size and read wall time.

Drives ``preserf_fortran_test_perf_smoke`` (see
``tests/fortran/unit/m_preserf/test_perf_smoke.f90``) and asserts the
measurements the fixture reports:

* ``baseline`` writes one 128 MiB ``real64`` field through both backends
  with no compression request. The store must be the uncompressed raw
  payload: the netcdf4 file within a header allowance of the raw bytes,
  the nczarr-v2 directory within a few percent (its size is summed here
  because the Fortran fixture cannot size a directory portably).
* ``compressed`` repeats the netcdf4 run with the store-wide compression
  knob and must land below half the raw payload. The nczarr-v2
  compressed measurement waits on its codec follow-up (issue #111),
  which rejects the combination at initialization.
* ``perturb-timing`` measures the read-perturb path against an
  in-fixture per-element RNG pass; the batched path must be measurably
  cheaper, and the read wall times must stay inside the smoke budget.

``PRESERF_PERF_READ_BUDGET_S`` overrides the per-read wall-time budget
(default 60 s). It is a smoke bound for pathological slowdowns, not a
benchmark regression gate.
"""

from __future__ import annotations

import os
import re
import subprocess
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from pathlib import Path

_MIB = 1024 * 1024
_METRIC = re.compile(r"^preserf-perf: scenario=(?P<scenario>\S+) (?P<pairs>.+)$")


def run_perf_scenario(
    binary: Path, out_dir: Path, scenario: str
) -> dict[tuple[str, str], dict[str, float]]:
    """Run one perf scenario, returning its metrics keyed by (scenario, backend).

    The fixture prints one ``preserf-perf: scenario=<name> backend=<name>
    key=value ...`` line per measured store and exits 0 with a
    ``preserf-perf: <scenario> OK`` marker only when its own assertions
    (netcdf4 store size, batched-versus-per-element ratio) hold.
    """
    out_dir.mkdir()
    result = subprocess.run(
        [str(binary), str(out_dir), scenario],
        capture_output=True,
        text=True,
        check=False,
        timeout=300,
    )
    assert result.returncode == 0, (
        f"perf fixture exited {result.returncode} for {scenario!r}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert f"preserf-perf: {scenario} OK" in result.stdout, (
        f"missing {scenario!r} OK marker.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )

    metrics: dict[tuple[str, str], dict[str, float]] = {}
    for line in result.stdout.splitlines():
        match = _METRIC.match(line)
        if match is None:
            continue
        pairs = dict(item.split("=", 1) for item in match["pairs"].split())
        backend = pairs.pop("backend")
        metrics[(match["scenario"], backend)] = {
            key: float(value) for key, value in pairs.items()
        }
    return metrics


def read_budget_s() -> float:
    """Per-read wall-time smoke budget, overridable for slower hosts."""
    return float(os.environ.get("PRESERF_PERF_READ_BUDGET_S", "60"))


def directory_bytes(root: Path) -> int:
    """Total size of every regular file under ``root``."""
    return sum(path.stat().st_size for path in root.rglob("*") if path.is_file())


def test_default_off_baseline_store_size_and_read_time(
    tmp_path: Path, fortran_perf_binary: Path
) -> None:
    """Both backends store the default-off field uncompressed; reads stay in budget."""
    metrics = run_perf_scenario(fortran_perf_binary, tmp_path / "perf", "baseline")

    netcdf4 = metrics[("baseline", "netcdf4")]
    raw = int(netcdf4["raw_bytes"])
    assert raw == 16 * _MIB * 8  # 128 MiB of real64
    # Contiguous default layout: payload plus a small header, nothing else.
    assert raw <= int(netcdf4["store_bytes"]) <= raw + _MIB

    nczarr = metrics[("baseline", "nczarr-v2")]
    assert nczarr["store_bytes"] == -1  # not sizeable from Fortran
    store = tmp_path / "perf" / "fperfz.zarr"
    assert store.is_dir(), "nczarr-v2 backend did not create a directory store"
    nczarr_bytes = directory_bytes(store)
    # The backend's default layout is uncompressed, so the store tracks the
    # raw payload within metadata/chunk padding.
    assert raw <= nczarr_bytes <= raw * 1.05 + _MIB

    budget = read_budget_s()
    for (_, backend), values in metrics.items():
        assert values["read_s"] < budget, (
            f"{backend} read took {values['read_s']}s, over the {budget}s budget"
        )


def test_compressed_store_is_smaller_and_reads_within_budget(
    tmp_path: Path, fortran_perf_binary: Path
) -> None:
    """The compressed netcdf4 store deflates the field well below its raw bytes."""
    metrics = run_perf_scenario(fortran_perf_binary, tmp_path / "perf", "compressed")
    values = metrics[("compressed", "netcdf4")]
    raw = int(values["raw_bytes"])
    assert int(values["store_bytes"]) < raw / 2, (
        "compressed store should be well below the raw payload: "
        f"{int(values['store_bytes'])} vs {raw}"
    )
    assert values["read_s"] < read_budget_s()


def test_perturb_timing_distinguishes_batched_from_per_element(
    tmp_path: Path, fortran_perf_binary: Path
) -> None:
    """Batched drawing costs measurably less than a per-element RNG pass."""
    metrics = run_perf_scenario(
        fortran_perf_binary, tmp_path / "perf", "perturb-timing"
    )
    values = metrics[("perturb-timing", "netcdf4")]
    per_element = values["per_element_s"]
    batched = values["batched_reference_s"]
    overhead = values["apply_overhead_s"]

    assert per_element > 0.0
    assert batched < 0.9 * per_element, (
        "the fixture is too small or the machine too noisy to distinguish "
        f"batched from per-element drawing: {batched}s vs {per_element}s"
    )
    # The production read-perturb path must apply draws in batches: its
    # overhead over a plain read sits near the batched reference, not the
    # per-element pass.
    assert overhead < 0.9 * per_element, (
        "read-perturb applies draws per element: overhead "
        f"{overhead}s vs per-element {per_element}s"
    )
    assert values["perturb_read_s"] < read_budget_s()
