# Proposal

## Why

A pre-development review verified three miscompilations of valid
free-form Fortran in the `!$SER` engine: comments or blank lines
between a continued subprogram header and its continuation drop the
continuation and displace the injected `USE` block; the
intent-qualifier-to-`::` span cannot cross the colon inside
`dimension(:)`, so a legal attribute order keeps `INTENT(IN)` where
read mode must assign; and the intent scanner runs ahead of directive
recognition with a comment-matching gate, so annotated directives are
dropped.

## What Changes

- Consume only `&`-prefixed lines in the standalone-subprogram lookahead
- Make the intent span paren-aware so attribute order no longer decides stripping
- Recognize directives before intent scanning; strip trailing comments before the `::` gate
- Exempt computed (write-only) DATA values from intent-removal recording
- Regression tests for all four; hoist inline comment-stripping patterns to module constants

## Out of Scope

- Fixed-form sources and tab-indented directives (consistent with the reference `pp_ser`)
- Merging the per-line regex scans, collapsing the two-pass model, or memoizing per-file analysis

## Capabilities

### Modified Capabilities

- `preprocessor`: scope tracking gains continuation robustness; read-mode intent stripping gains attribute-order independence, comment immunity, and a computed-value exemption

## Impact

`src/preserf/preprocessor.py`, `tests/unit_tests/test_preprocessor.py`, CHANGELOG.
