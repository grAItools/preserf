# Spec Delta

## Purpose

Keep the fast pytest slice free of artifact construction, and pin the CLI's behavior on degenerate input files so refactors cannot silently introduce tracebacks.

## ADDED Requirements

### Requirement: Boundary-input robustness

The CLI SHALL handle degenerate input files without unhandled tracebacks: empty files, CRLF-terminated sources, and non-UTF-8 bytes either preprocess to a defined output or fail with a one-line diagnostic, and the documented behavior is pinned by tests.

#### Scenario: Empty file

- **WHEN** an explicitly named input file is empty
- **THEN** the CLI completes without an unhandled traceback

#### Scenario: CRLF source

- **WHEN** an input file uses CRLF line endings
- **THEN** the preprocessed output preserves the directive line structure without corruption

#### Scenario: Non-UTF-8 bytes

- **WHEN** an input file contains bytes that do not decode as UTF-8
- **THEN** the CLI either processes the file or reports a one-line diagnostic, never an unhandled traceback
