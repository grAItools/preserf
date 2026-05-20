# Testing strategy

## What the agent runs

- **Pre-claim-done gate**: `make verify` (= `scripts/verify.sh`).
- **Fast loop**: `make test` — must finish in <60s. Add slow suites under
  `make test-all`.

## Layering

_Fill in: unit, integration, contract, e2e. Where each lives, what each
covers, when to add to which layer._

## Coverage targets

_Fill in: numeric or qualitative targets. Coverage is a smoke detector, not
a goal — don't write tests just to hit a number._

## Determinism

- Time, randomness, and I/O must be injectable.
- Snapshot tests are fine but commit the fixture, not the snapshot run output.
- Flaky tests are bugs; quarantine them in a separate target and open an issue,
  don't `@retry`.
