# Tasks

## 1. Regression tests (fail first)

- [x] 1.1 Add a reproducer where a comment intervenes between a `&`-continued standalone subprogram header and its continuation; assert the continuation survives and the `USE` block follows the completed header
- [x] 1.2 Add a reproducer for `integer, intent(in), dimension(:) :: vn` with a `!$SER DATA` directive naming `vn`; assert the qualifier is stripped in the serialize branch exactly as for the reverse attribute order
- [x] 1.3 Add a reproducer for a `!$SER DATA` directive whose trailing comment mentions `intent(in) :: <field>`; assert the `SELECT CASE` expansion is present and no spurious `#ifdef/#else` block wraps the directive
- [x] 1.4 Add a reproducer where a `!$SER DATA` value is computed (e.g. `vn = a*b`) and `vn` is declared `intent(in)`; assert no `#ifdef/#else` intent-strip block is emitted for its declaration

## 2. Fixes

- [x] 2.1 Rework `_scan_subprogram`'s lookahead to consume only `&`-prefixed lines (`src/preserf/preprocessor.py:448-458`)
- [x] 2.2 Make `_RE_INTENT_IN`'s qualifier-to-`::` span paren-aware (`preprocessor.py:146-148`)
- [x] 2.3 Reorder the per-line dispatch so directive recognition precedes intent scanning, and strip trailing comments before the `::` gate (`preprocessor.py:403`, `:486`)
- [x] 2.4 Stop recording intent removal for values the computed-value classifier already marks write-only (`preprocessor.py:1057-1062`)
- [x] 2.5 Hoist the inline `re.sub(r"!.*")` patterns in the touched regions to module constants

## 3. Verification

- [x] 3.1 Add the CHANGELOG bullet under `[Unreleased]`
- [x] 3.2 Run `pixi run verify` and confirm it is green
