# Preprocessor Specification

## Purpose

Expand `!$SER` directives embedded in Fortran source into explicit calls to the serialization runtime, as a typed port of Serialbox's `pp_ser.py`. Covers the directive grammar, the two-pass processing model, scope tracking, and error reporting.

## Requirements

### Requirement: Directive recognition

The preprocessor SHALL recognize `!$SER` directives (case-insensitive, optional leading spaces — tabs are not recognized) on `.f90`, `.f`, `.f03`, `.inc`, and `.incf` files, with all directive keywords and their abbreviations matched case-insensitively while preserving the case of arguments.

#### Scenario: Abbreviated keyword

- **WHEN** a source line contains `!$ser dat x=y`
- **THEN** the directive is parsed as `DATA` and expanded identically to the full spelling

### Requirement: Two-pass processing

The preprocessor SHALL process each file in two passes: an analysis pass that collects every serialization API call required by the source, and a generation pass that injects the corresponding `USE` imports and rewrites each directive as a guarded block of Fortran calls. By default expansions are guarded by `#ifdef SERIALIZE` / `#endif`; an empty `Options.ifdef` disables the guards.

#### Scenario: USE import injection

- **WHEN** a module contains a `!$SER DATA` directive
- **THEN** the generated output imports `fs_write_field`/`fs_read_field` (from the configured serialization module) and the always-required `ppser_*` utility symbols, and each expanded call is guarded by `#ifdef SERIALIZE`

### Requirement: Scope tracking

The preprocessor SHALL track `MODULE`/`PROGRAM` scoping units: a `USE` block is emitted once after the enclosing `MODULE`/`PROGRAM` header and suppressed for directives in contained subprograms. Standalone subprograms (outside a module) each receive their own `USE` block after their header, including continuation lines.

#### Scenario: Standalone subprogram with continuation

- **WHEN** a standalone subroutine header spans continuation lines and contains a directive
- **THEN** the `USE` block is inserted after the full header, including continuations

#### Scenario: Standalone nested subprograms

- **WHEN** two standalone subprograms outside any module each contain a directive
- **THEN** each gets its own `USE` block; suppression applies only within `MODULE`/`PROGRAM` scope

### Requirement: Continuation comment tolerance

Comments and blank lines between the continuation lines of a standalone subprogram header SHALL be preserved and SHALL NOT displace the injected `USE` block or cause continuation lines to be dropped.

#### Scenario: Comment between continuation lines

- **WHEN** a comment or blank line appears between a `&`-continued standalone subprogram header and its remaining continuation lines
- **THEN** every continuation line survives preprocessing unchanged and the `USE` block is injected after the completed header

### Requirement: Line continuation

Directives SHALL support multi-line form: a body ending in `&` continues on lines prefixed `!$SER&`; an unterminated continuation or a non-prefixed continuation line SHALL raise an error. A `&` inside a trailing comment SHALL NOT count as a continuation.

#### Scenario: Continuation error

- **WHEN** a directive's continuation runs past the end of file or the next line lacks the `!$SER&` prefix
- **THEN** processing fails with `DirectiveError` naming the file and line

### Requirement: Directive vocabulary

The preprocessor SHALL expand the full directive set: `INIT`, `CLEANUP`, `DATA`, `DATA_KBUFF`, `ACCDATA`, `MODE`, `OPTION`, `METAINFO`, `VERBATIM`, `REGISTER`, `REGISTERTRACERS`, `ZERO`, `SAVEPOINT`, `TRACER`, `ON`, `OFF`, each with the argument grammar (positionals, `key=value` pairs, trailing `IF` clause) documented in `dev/references/directives_specification.md` — which is the upstream reference; preserf's divergences from it are marked inline there and pinned by the differential test.

#### Scenario: OPTION accepts only the runtime's fixed keyword

- **WHEN** an `!$SER OPTION` directive names any key other than `verbosity` (case-insensitive; `off`/`on` map to `0`/`1`)
- **THEN** the preprocessor raises a `DirectiveError` naming the unsupported key, because the runtime's `fs_Option` exposes only that keyword (ADR 0003)

#### Scenario: DATA with computed values

- **WHEN** a `!$SER DATA` value contains top-level arithmetic or a top-level `merge` intrinsic (e.g. `a*b`, `a+1`, `merge(a,b,c)`)
- **THEN** it is classified as computed and only written, never read back; arithmetic inside subscripts (e.g. `arr(i-1)`) remains a plain field reference that is also read back

### Requirement: Field registration shortcuts

The `REGISTER` directive SHALL accept the dimension shortcuts (`I`, `J`, `K`, `IJ`, `IJK`, ...), each expanding to the canonical 12-value `iSize ... lPlusHalo` list.

#### Scenario: IJ shortcut

- **WHEN** a register directive uses the `IJ` shortcut
- **THEN** it expands to `ie je 0 0 nboundlines nboundlines nboundlines nboundlines 0 0 0 0`

### Requirement: Read-mode intent stripping

For fields named by `DATA`/`ACCDATA`/`DATA_KBUFF` in a scope where the declaration carries `INTENT(IN)`, the generated declarations SHALL strip the intent in read modes so read-mode code can assign into them. Stripping SHALL be independent of declaration attribute order, and SHALL NOT be triggered by `!$SER` directive lines or by `intent(in)` text appearing in comments. Values the computed-value classification already marks write-only SHALL be exempt from intent-removal recording.

#### Scenario: Read mode assignment

- **WHEN** the serializer runs in read mode and the directive references an `intent(in)` local
- **THEN** the emitted declaration change allows assignment of the deserialized value

#### Scenario: Attribute order independence

- **WHEN** a declaration spells the qualifier as `integer, intent(in), dimension(:) :: vn`
- **THEN** the qualifier is stripped exactly as for `integer, dimension(:), intent(in) :: vn`

#### Scenario: Directive comments never trigger stripping

- **WHEN** a `!$SER DATA` directive carries a trailing comment mentioning `intent(in) :: <field>` for a field named by the directive
- **THEN** the directive expands normally and no `#ifdef/#else` block is emitted around it

#### Scenario: Computed values are exempt

- **WHEN** a `DATA` value is classified computed (write-only) by the top-level arithmetic and merge-intrinsic rules
- **THEN** no intent-removal entry is recorded for it, so its declaration is left untouched

### Requirement: Errors carry context

All directive errors SHALL raise `DirectiveError` carrying the file name and line number of the offending directive.

#### Scenario: Unknown directive keyword

- **WHEN** a directive uses an unrecognized keyword
- **THEN** the raised `DirectiveError` message includes the file, the line number, and the directive text

### Requirement: Differential parity with reference pp_ser

On the designated agreement corpus, the preprocessor's expansion SHALL produce the same normalized sequence of runtime calls as the reference Serialbox `pp_ser` preprocessor (serialization intent, not byte-identical text), verified by the test-only `serialbox4py` comparison suite. Intentional divergences from the reference — e.g. the corrected handling of subscript arithmetic in `!$SER DATA` values — are preserved and covered by their own tests.

#### Scenario: Golden expansion

- **WHEN** the differential test preprocesses a shared agreement-corpus fixture with both preserf and the reference `pp_ser`
- **THEN** the normalized runtime-call sequences match

#### Scenario: Intentional divergence stays divergent

- **WHEN** a fixture exercises subscript arithmetic in a DATA value (where preserf fixed a reference bug)
- **THEN** the normalized calls differ from the reference by design, and the difference is asserted, not accidental

### Requirement: Mode value normalization

The MODE directive SHALL resolve its argument against the predefined mode names case-insensitively, substituting the numeric value on a match; an argument that matches no predefined name SHALL pass through verbatim.

#### Scenario: Case-insensitive resolution

- **WHEN** a `!$SER MODE` directive names a predefined mode in any casing (for example `WRITE`, `Cpu`, `gpu`)
- **THEN** the expanded call passes the numeric value, not the raw spelling

#### Scenario: Unknown value passes through

- **WHEN** a `!$SER MODE` argument matches no predefined name
- **THEN** the argument is emitted verbatim in the expanded call
