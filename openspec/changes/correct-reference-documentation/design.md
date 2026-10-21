# Design

## Context

The living specs survived every spot-check the review ran against the
implementation; the drift lives in `dev/references/` — the
`directives_specification.md` header promises `**preserf note**` markers
for divergences but several rows carry none, and one row (MODE
case-sensitivity) directly contradicts the code. The CHANGELOG's
`[Unreleased]` section is thorough but its group headings drifted into
non-standard and duplicated forms. The hygiene policy that bans "Slice X"
process labels is enforced in code comments by tests but not in the
reference docs.

## Goals / Non-Goals

**Goals:**

- No reference-doc statement contradicts implemented behavior.
- Rows describing upstream-only behavior carry the marker the header
  promises.
- The living spec pins MODE value normalization so the contract is
  explicit.

**Non-Goals:**

- Living-spec behavior changes (all five verified accurate) and any code
  changes.
- A commit-by-commit CHANGELOG audit; the consolidation is structural.

## Decisions

- Correct the MODE sentence to "case-insensitive" and pin the behavior as
  a spec requirement rather than keeping the contradiction.
- Annotate the unmarked upstream-only rows (`verbose`, `identical`, the
  phantom error) with the `**preserf note**` marker or delete rows that
  describe conditions the implementation cannot produce.
- Replace the regex-matching sentence in §3.10 with the exact
  table-lookup semantics.
- Rewrite the editorial "Wait —" block as one declarative sentence.
- Strip "(as of Slice A-1)" — the sentence's content is already stated as
  current fact.
- Consolidate CHANGELOG groups into ordered Keep-a-Changelog blocks and
  reword the `.gemini` entry to lead with what changed.

## Risks / Trade-offs

- None functional: documentation and spec-delta only. The largest risk is
  doc churn during merge; the edits are localized sentences.
