# Spec Delta

## Purpose

Pin the MODE directive's case-insensitive value resolution as a specified behavior, closing the gap between the reference doc's case-sensitive claim and the implementation.

## ADDED Requirements

### Requirement: Mode value normalization

The MODE directive SHALL resolve its argument against the predefined mode names case-insensitively, substituting the numeric value on a match; an argument that matches no predefined name SHALL pass through verbatim.

#### Scenario: Case-insensitive resolution

- **WHEN** a `!$SER MODE` directive names a predefined mode in any casing (for example `WRITE`, `Cpu`, `gpu`)
- **THEN** the expanded call passes the numeric value, not the raw spelling

#### Scenario: Unknown value passes through

- **WHEN** a `!$SER MODE` argument matches no predefined name
- **THEN** the argument is emitted verbatim in the expanded call
