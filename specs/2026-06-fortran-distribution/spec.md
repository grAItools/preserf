# Fortran distribution: ship the runtime + a CMake helper in the wheel

## Problem

`preserf` expands `!$SER` directives into explicit Fortran calls
(`USE m_serialize`, `USE utils_ppser`, `fs_*` / `ppser_*`) that only
compile against the Fortran runtime helper modules. Those modules live at
`src/preserf-fortran/`, but the wheel bundles only `src/preserf`
(`pyproject.toml`); because `pip` builds that same wheel even when it installs
from an sdist, **no install path ships the runtime**. An installed `preserf`
therefore provides the preprocessor but nothing to compile its output against.

The only existing way to obtain the runtime is to clone the repository, and
the only user-facing integration example is the hand-wired
`examples/laplacian/CMakeLists.txt` (the in-repo `tests-fortran/` tree wires
the runtime the same way for CI): a relative
`add_subdirectory(../../src/preserf-fortran)`, a `find_program(preserf)`, an
`add_custom_command` that runs the CLI to expand `.f90` → `.F90`, a
`target_link_libraries(... preserf_fortran)`, and a `SERIALIZE` compile
definition. Every downstream user must rediscover and re-assemble that
recipe by hand against a path that only exists in a source checkout.

## Goal

A `pip install preserf` user can compile preserf-generated Fortran in their
own project with minimal ceremony: the Fortran runtime sources travel with
the installed package, the package can tell a build system where they are,
and a ready-made CMake helper encapsulates the expand-and-link workflow so
the user writes one function call instead of re-deriving the recipe.

## Confirmed design decisions

These were chosen with the requester and bound the scope:

- **Build system: CMake only.** It is the dominant Fortran build system in
  this domain (climate/weather, Serialbox heritage) and the repo already
  standardizes on it. fpm and Meson helpers are out of scope for this slice.
- **Distribution form: source only.** Fortran `.mod` files are
  compiler-and-version specific, and the runtime links `netcdf-fortran` via
  pkg-config; a prebuilt static library would only work for one exact
  toolchain. Users compile the bundled sources with their own compiler
  against their own `netcdf-fortran`.
- **Layout: the Fortran tree moves under the Python package**
  (`src/preserf-fortran/` → `src/preserf/fortran/`) so it is natural package
  data and the in-tree and installed layouts match exactly.
- **Helper depth: a rich CMake helper** — a single function that captures the
  whole expand → compile → link → `SERIALIZE` workflow, not merely a
  documented recipe.

## Non-goals

- fpm / Meson configuration helpers (possible future slice; the path-printing
  discovery command is the interim fallback for non-CMake users).
- Shipping compiled artifacts (`.mod`, static/shared libraries) or vendoring
  `netcdf-fortran` — it remains a user-supplied system dependency.
- Building Fortran during `pip install` (no compile-at-install step; sources
  are compiled by the user's own project build).
- Reconciling the duplicated version strings (`pyproject.toml` vs the Fortran
  `CMakeLists.txt` `project(VERSION ...)`); tracked separately.
- Any change to directive semantics or the generated code.

## Success criteria

- A built wheel contains the Fortran runtime (`.F90` / `.f90` / `.inc` /
  version template / `CMakeLists.txt`) and the CMake helper module under the
  installed `preserf` package.
- `preserf` exposes the bundled location both as a Python API and as a CLI
  command that prints the absolute path, so a build system can discover it
  without knowing install internals (the numpy `get_include()` pattern).
- A bundled CMake helper provides a single function that, given a target and
  one or more `!$SER` source files, runs the `preserf` CLI to expand them,
  compiles and links them against the runtime library, and applies the
  `SERIALIZE` definition and required Fortran flags — reproducing what
  `examples/laplacian/CMakeLists.txt` does today by hand.
- The in-tree example and the Fortran e2e test consume that **same** helper,
  so the shipped integration recipe is continuously exercised and cannot
  drift from what users get.
- An external-consumer test builds a small project against the **bundled**
  runtime (resolved via the discovery command, not the in-tree checkout),
  compiles it, runs it, and validates the resulting netCDF store round-trips.
- A packaging test asserts the runtime files and helper are present in a
  freshly built wheel and that the discovery API/CLI resolve to them.
- The move leaves the existing Fortran build, unit tests, e2e tests, and the
  laplacian example green (all moved-path references updated); `pixi run
  verify` passes and the slow consumer test runs under `pixi run test-all`.
- User-facing documentation shows the end-to-end "use preserf in your build"
  flow and states the unchanged system prerequisites (a Fortran compiler,
  `netcdf-fortran` via pkg-config, CMake ≥ 3.20).

## Open questions for the architect

- Exact name/shape of the discovery surface (function name, whether the CLI
  exposes a flag like `--fortran-dir` versus a subcommand) — the CLI is
  currently a single-command Typer app, which constrains the choice.
- Whether the packaging-presence check belongs in the fast `verify` gate
  while the compile-and-run consumer test stays in the slow `test-all`.

> A fully worked, phase-by-phase technical design for this spec already exists
> (decisions, file-level changes, the CMake helper sketch, the verification
> strategy, and risks). The architect should fold it into `plan.md` during the
> `/plan` phase rather than re-deriving it.
