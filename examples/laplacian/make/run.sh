#!/usr/bin/env bash
# preserf example driver (non-CMake consumer): install the runtime with CMake,
# then preprocess + compile + link with plain GNU make.
#
# This runs the SAME laplacian program as the cmake/ variant next door, but
# instead of consuming the runtime through the shipped PreserfFortran.cmake
# helper it:
#   1. builds + INSTALLS the preserf_fortran library with CMake into a local
#      prefix (the only CMake step — yields a plain library + .mod + config), and
#   2. drives the preserf expansion and the gfortran compile/link from a
#      hand-written Makefile against that install prefix.
#
# Run inside the `examples` pixi env (preserf, cmake, gfortran, make and
# netcdf-fortran all on PATH):
#
#   pixi run -e examples bash examples/laplacian/make/run.sh
#
# Produces:
#   prefix/                 the installed runtime (lib + include/*.mod + cmake/)
#   build/laplacian.F90     expanded source (the !$SER directives made explicit)
#   build/laplacian         the compiled binary; run as `laplacian <outdir> [nsteps]`
#   out/laplacian.nc        the serialized store, one savepoint per time step
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="$DIR/prefix"
RUNTIME_BUILD="$DIR/build/runtime"
OUT="$DIR/out"

mkdir -p "$OUT"

# A build/ left over from a different checkout location carries a stale
# CMakeCache that makes reconfigure abort; drop it so re-runs just work.
if [ -f "$RUNTIME_BUILD/CMakeCache.txt" ]; then
    cached_src="$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$RUNTIME_BUILD/CMakeCache.txt")"
    if [ "$cached_src" != "$(preserf --fortran-dir)" ]; then
        echo "==> removing stale runtime build cache (was: $cached_src)"
        rm -rf "$RUNTIME_BUILD"
    fi
fi

# 1. Build + install the runtime library with CMake. This is the ONLY CMake
#    step: it compiles src/preserf/fortran into libpreserf_fortran.a and
#    installs it, its .mod interface files, and a package config under PREFIX.
#    -DCMAKE_INSTALL_LIBDIR=lib pins the lib dir so the Makefile can rely on
#    $(PREFIX)/lib (GNUInstallDirs would pick lib64 on some distros).
echo "==> cmake: build + install the preserf_fortran runtime into $PREFIX"
cmake -S "$(preserf --fortran-dir)" -B "$RUNTIME_BUILD" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_LIBDIR=lib
cmake --build "$RUNTIME_BUILD" --target install

# 2. Preprocess + compile + link with plain make against the install prefix.
echo "==> make: expand !\$SER, compile and link against the installed library"
make -C "$DIR" PREFIX="$PREFIX"

# 3. Run the binary; it writes the store into out/. Pass a second argument
#    (e.g. `build/laplacian "$OUT" 5`) to change the number of iterations.
echo "==> run: iterating the Laplacian and serializing each step"
"$DIR/build/laplacian" "$OUT"

echo
echo "Store written to: $OUT/laplacian.nc"
echo "Verify and plot it with (verify.py is shared with the cmake/ variant):"
echo "  pixi run -e examples python $DIR/../verify.py $OUT/laplacian.nc"
