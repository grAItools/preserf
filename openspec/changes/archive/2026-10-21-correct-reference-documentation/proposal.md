# Proposal

## Why

The reference docs contradict the code in exactly one place —
`dev/references/directives_specification.md:471` asserts MODE matching
is **case-sensitive** while `preprocessor.py:884` deliberately
lower-cases — plus unmarked upstream-only rows (§6 `verbose`/
`identical`; §7 an error never raised; §3.10 a regex claim where the
implementation is an exact dict lookup), an editorial "Wait —" block
frozen into the REGISTER section, a "Slice A-1" process label the
repo's own hygiene policy bans, CHANGELOG `[Unreleased]` group-heading
drift, and a stale legacy-tree pointer in ADR 0006.

## What Changes

- Correct or annotate every flagged row; rewrite the editorial block as declarative prose; strip the process label
- Consolidate the CHANGELOG `[Unreleased]` groups and re-file the ambiguous `.gemini` entry
- Pin case-insensitive MODE value resolution in this change's spec delta so the behavior is specified, not just implemented

## Out of Scope

- Living-spec behavior changes beyond the MODE pinning delta (all five specs verified accurate) and any code changes

## Capabilities

### Modified Capabilities

- `preprocessor`: a new mode-value normalization requirement pins that predefined mode names resolve case-insensitively and unknown values pass through verbatim

## Impact

`dev/references/` (both files), `CHANGELOG.md`, ADR 0006, this change's spec delta. No code changes.
