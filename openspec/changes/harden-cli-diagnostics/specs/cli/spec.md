# Spec Delta

## Purpose

Make the CLI's failure modes and input handling match its one-line-diagnostic contract, and pin single-destination semantics for stdout runs.

## MODIFIED Requirements

### Requirement: Error reporting

Directive errors SHALL surface as CLI failures that print the `DirectiveError` message (file and line) and exit non-zero. Operating-system errors raised while collecting input files (permission denied, unreachable paths) SHALL surface through the same one-line failure path rather than an unhandled traceback.

#### Scenario: Malformed directive

- **WHEN** a processed file contains a directive with a bad continuation
- **THEN** the CLI reports the file and line and exits non-zero

#### Scenario: Unreadable input directory

- **WHEN** an input directory cannot be walked due to a permission error
- **THEN** the CLI prints a one-line diagnostic naming the failing path and exits non-zero

## ADDED Requirements

### Requirement: Input validation

The CLI SHALL require an explicit output destination (`--output` or `--output-dir`) when more than one input file is collected, and SHALL warn when an explicitly named file argument does not look like Fortran source.

#### Scenario: Multiple sources without a destination

- **WHEN** two or more input files are given with neither `--output` nor `--output-dir`
- **THEN** the CLI fails with a usage error before preprocessing anything

#### Scenario: Non-Fortran explicit argument

- **WHEN** an explicitly named file argument carries a non-Fortran suffix
- **THEN** the CLI emits a warning to stderr and continues processing
