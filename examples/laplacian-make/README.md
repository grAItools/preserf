# Laplacian example — plain-`make` consumer of the installed library

This is the **same** Laplacian program as [`../laplacian`](../laplacian/) (it
reuses that directory's `laplacian.f90` source and `verify.py` checker), built a
different way: instead of consuming the preserf runtime through the shipped
`PreserfFortran.cmake` helper, it

1. **builds and installs** the `preserf_fortran` library with CMake into a local
   `prefix/` — the only CMake step, producing a plain static library, its
   compiled `.mod` interface files, and a package config; then
2. **drives the preprocessing, compilation and linking from a hand-written
   [`Makefile`](Makefile)** against that install prefix.

It exists to show that the install target makes the runtime consumable by **any**
build system — you are not required to use CMake for your own code. It also
spells out, explicitly, the compile/link recipe the CMake helper otherwise
applies for you.

## The two steps

```sh
# 1. Build + install the runtime with CMake (the only CMake involvement).
cmake -S "$(preserf --fortran-dir)" -B build/runtime \
    -DCMAKE_INSTALL_PREFIX="$PWD/prefix" -DCMAKE_INSTALL_LIBDIR=lib
cmake --build build/runtime --target install

# 2. Preprocess + compile + link your own code with plain make.
make PREFIX="$PWD/prefix"
```

`run.sh` does exactly this, then runs the binary.

## What the Makefile has to do (and the CMake helper hides)

`find_package`/`-lpreserf_fortran` only gives you the _library_. Turning a
`!$SER`-annotated source into a serializing binary still needs the preprocessor
step and a specific set of compiler flags — the same recipe documented for the
CMake helper, here applied by hand:

| Step    | Command                                                                                                | Why                                                                                                                                                                                                                           |
| ------- | ------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Expand  | `preserf laplacian.f90 -o build/laplacian.F90`                                                         | turn `!$SER` comments into real calls; the `.F90` (uppercase) name makes the compiler run cpp                                                                                                                                 |
| Compile | `gfortran -cpp -DSERIALIZE -ffree-line-length-none -std=f2008 -I<prefix>/include/preserf_fortran -c …` | `-cpp`/`-DSERIALIZE` activate the `#ifdef SERIALIZE` calls; `-ffree-line-length-none` keeps preserf's long generated lines from truncating at column 132; `-std=f2008` matches the runtime; `-I…` finds the installed `.mod`s |
| Link    | `gfortran … -L<prefix>/lib -lpreserf_fortran $(pkg-config --libs netcdf-fortran)`                      | link the static runtime **and** its public `netcdf-fortran` dependency (a static archive carries no link interface), netcdf **after** preserf                                                                                 |

## Run it

```sh
pixi run -e examples bash examples/laplacian-make/run.sh
pixi run -e examples python examples/laplacian/verify.py examples/laplacian-make/out/laplacian.nc
```

This writes `prefix/` (the install), `build/` (expanded source, objects,
binary), and `out/laplacian.nc` (the store). `verify.py` — shared with the
CMake example — re-runs the iteration in numpy and confirms every step matches.

## A note on conda/pixi environments

An activated conda/pixi env exports `BUILD` (the build triple) and `PREFIX`
(the env root). `make` lets an environment variable override a `?=` default, so
the Makefile uses plain `:=` for its directory/prefix variables (a command-line
`make PREFIX=…` still wins) and guards against a `PREFIX` that doesn't actually
contain the installed modules.
