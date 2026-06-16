"""Differential test: preserf vs the upstream Serialbox ``pp_ser`` it ports.

preserf re-implements ``pp_ser``, expanding ``!$SER`` directives into calls
against the *same* Serialbox Fortran runtime API (``fs_*`` / ``ppser_*``).
Rather than only checking preserf against hand-written expectations (which can
encode the same misunderstanding the code has), this pins preserf against
**external ground truth**: the vendored upstream ``vendor/pp_ser.py``
(Serialbox 2.6.3), run on the same inputs. We compare the normalized sequence
of generated runtime calls — *serialization intent*, not byte-for-byte text —
because that is where real bugs live (e.g. issue #103: subscript arithmetic
wrongly dropped on read).

Two tiers:

* **Agreement** — directives where preserf must match upstream exactly.
* **Intentional divergence** — preserf deliberately reads back indexed values
  whose subscripts contain arithmetic (``arr(i+1)``), which upstream
  misclassifies as write-only. Pinned explicitly so the divergence stays
  intentional and visible: the test fails if preserf regresses to dropping the
  read (re-breaking #103) or if the vendored upstream behaviour changes.
"""

from __future__ import annotations

import pytest

from preserf.preprocessor import Options, Preprocessor
from tests._support.ppser_reference import expand_with_ppser, extract_runtime_calls

_MODULE = "module m\n{body}\nend module m\n"


def _preserf_calls(source: str) -> list[str]:
    return extract_runtime_calls(Preprocessor("input.f90", source, Options()).process())


def _ppser_calls(source: str) -> list[str]:
    return extract_runtime_calls(expand_with_ppser(source))


# Directives where preserf must reproduce upstream pp_ser exactly. Values used in
# DATA here are deliberately on the *agreeing* side of the read-back boundary:
# plain scalars and full-slice subscripts (read back by both), and top-level
# computed expressions (write-only in both).
_AGREEMENT_CASES = {
    "init": "!$SER INIT directory='./data' prefix='field'",
    "savepoint_metainfo": "!$SER SAVEPOINT sp1 step=ntstep",
    "mode_write": "!$SER MODE write",
    "mode_read": "!$SER MODE read",
    "data_scalar": "!$SER DATA fld=x",
    "data_full_slice": "!$SER DATA u=u(:,:,:,n)",
    "data_multi_scalar": "!$SER DATA a=a b=b c=c",
    "data_sum_write_only": "!$SER DATA w=a+b",
    "data_merge_write_only": "!$SER DATA w=merge(a,b,c)",
    "data_unary_write_only": "!$SER DATA w=-x",
    "cleanup": "!$SER CLEANUP",
    "sequence": (
        "!$SER INIT directory='.' prefix='p'\n"
        "!$SER SAVEPOINT sp step=n\n"
        "!$SER DATA u=u(:,:,:,n) v=v\n"
        "!$SER CLEANUP"
    ),
}


@pytest.mark.parametrize(
    "body", _AGREEMENT_CASES.values(), ids=list(_AGREEMENT_CASES.keys())
)
def test_preserf_matches_upstream_pp_ser(body: str) -> None:
    """preserf emits the same runtime calls as upstream pp_ser."""
    source = _MODULE.format(body=body)
    preserf = _preserf_calls(source)
    # Guard against a corpus/regex regression that yields empty output on both
    # sides, which would otherwise satisfy the equality below for the wrong
    # reason. Every agreement case generates at least one runtime call.
    assert preserf, "expected at least one runtime call from preserf"
    assert preserf == _ppser_calls(source)


# Indexed values whose subscripts contain arithmetic: preserf reads these back
# (issue #103), upstream pp_ser misclassifies them as computed and drops the read.
_DIVERGENCE_VALUES = ["arr(i-1)", "arr(i+1)", "arr(2*i)", "a(i)%b(j-1)"]


@pytest.mark.parametrize("value", _DIVERGENCE_VALUES)
def test_subscript_arithmetic_diverges_from_upstream(value: str) -> None:
    """preserf reads indexed-arithmetic values back; upstream pp_ser does not.

    This pins the #103 fix against external ground truth: a regression that
    re-dropped these reads would make preserf match upstream again and fail here.
    """
    source = _MODULE.format(body=f"!$SER MODE read\n!$SER DATA fld={value}")
    preserf = _preserf_calls(source)
    upstream = _ppser_calls(source)

    # Both tools write the field unconditionally.
    assert any(c.startswith("call fs_write_field") for c in preserf)
    assert any(c.startswith("call fs_write_field") for c in upstream)

    # preserf reads it back; upstream drops the read — the intentional divergence.
    assert any(c.startswith("call fs_read_field") for c in preserf)
    assert not any(c.startswith("call fs_read_field") for c in upstream)


def test_extract_runtime_calls_normalizes_fixture() -> None:
    """``extract_runtime_calls`` joins continuations and drops non-call lines.

    Direct smoke test of the riskiest helper, exercising the cases the
    differential test only hits transitively: a multi-line ``&``-continued
    ``call``, a ``! file: lineno:`` annotation, a ``USE`` block line, an inline
    trailing comment, and a plain single-line call.
    """
    fixture = (
        "! file: input.f90 lineno: 3\n"
        "        USE m_serialize\n"
        "        call fs_write_field(serializer, savepoint, 'u', u, &\n"
        "          1, 2, 3)\n"
        "        call fs_read_field(serializer, savepoint, 'v', v)  ! reads v\n"
    )
    assert extract_runtime_calls(fixture) == [
        "call fs_write_field(serializer, savepoint, 'u', u, 1, 2, 3)",
        "call fs_read_field(serializer, savepoint, 'v', v)",
    ]
