# Spec Delta

## Purpose

Close three verified miscompilation paths in the `!$SER` engine so legal free-form Fortran preprocesses correctly, and pin the intent machinery's independence from attribute order, comments, and computed-value classification.

## MODIFIED Requirements

### Requirement: Scope tracking

The preprocessor SHALL track `MODULE`/`PROGRAM` scoping units: a `USE` block is emitted once after the enclosing `MODULE`/`PROGRAM` header and suppressed for directives in contained subprograms. Standalone subprograms (outside a module) each receive their own `USE` block after their header, including continuation lines. Comments and blank lines between the continuation lines of a standalone subprogram header SHALL be preserved and SHALL NOT displace the injected `USE` block or cause continuation lines to be dropped.

#### Scenario: Standalone subprogram with continuation

- **WHEN** a standalone subroutine header spans continuation lines and contains a directive
- **THEN** the `USE` block is inserted after the full header, including continuations

#### Scenario: Standalone nested subprograms

- **WHEN** two standalone subprograms outside any module each contain a directive
- **THEN** each gets its own `USE` block; suppression applies only within `MODULE`/`PROGRAM` scope

#### Scenario: Comment between continuation lines

- **WHEN** a comment or blank line appears between a `&`-continued standalone subprogram header and its remaining continuation lines
- **THEN** every continuation line survives preprocessing unchanged and the `USE` block is injected after the completed header

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
