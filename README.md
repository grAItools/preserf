# preserf - Preprocessor for Fortran data serialization directives

`preserf` is a Python preprocessor that expands `!$SER` directives in Fortran
source into explicit serialization calls.

The repository contains two main pieces:

- `src/preserf/`: the preprocessor engine and CLI.
- `src/preserf-fortran/`: Fortran helper modules that provide the runtime API
  targeted by generated code.

## What it does

- Parses `!$SER` directives using a two-pass analysis/generation model.
- Injects the required `USE` imports and guarded serialization blocks.
- Expands directives such as `INIT`, `SAVEPOINT`, `DATA`, `REGISTER`, and
  related forms into Fortran API calls.
- Supports CLI processing of single files or directory trees.

## Development commands

- `pixi run test`: run the fast Python test suite.
- `pixi run lint`: run static checks.
- `pixi run fmt`: apply formatting.
- `pixi run verify`: run the full verification gate.

## Key documentation

- Project architecture overview: [docs/architecture.md](docs/architecture.md)
- Directive grammar and expansion contract:
  [docs/references/directives_specification.md](docs/references/directives_specification.md)
- Storage model mapping:
  [docs/references/storage_mapping.md](docs/references/storage_mapping.md)
- Fortran runtime helpers and compatibility details:
  [src/preserf-fortran/README.md](src/preserf-fortran/README.md)
- Testing strategy: [docs/testing.md](docs/testing.md)
- Code style guide: [docs/style.md](docs/style.md)
- Architecture decision records: [docs/adr/README.md](docs/adr/README.md)
