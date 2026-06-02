#!/usr/bin/env bash
# preserf example driver: preprocess -> build -> run.
#
# Run inside the `examples` pixi environment so `preserf`, `cmake`, and the
# Fortran/netcdf-fortran toolchain are all on PATH:
#
#   pixi run -e examples bash examples/laplacian/run.sh
#
# Produces:
#   build/laplacian.F90   expanded source (the !$SER directives made explicit)
#   build/laplacian       the compiled binary
#   out/laplacian.nc      the serialized store
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$DIR/build"
OUT="$DIR/out"

mkdir -p "$BUILD" "$OUT"

# 1. Expand the !$SER directives. Done explicitly (rather than from CMake) so
#    the generated Fortran is easy to open and read alongside the input.
echo "==> preserf: expanding !\$SER directives"
preserf "$DIR/laplacian.f90" -o "$BUILD/laplacian.F90"

# 2. Configure + build against the preserf_fortran helper.
echo "==> cmake: configuring and building"
cmake -S "$DIR" -B "$BUILD"
cmake --build "$BUILD"

# 3. Run the binary; it writes the store into out/.
echo "==> run: computing Laplacian and serializing"
"$BUILD/laplacian" "$OUT"

echo
echo "Store written to: $OUT/laplacian.nc"
echo "Plot it with:"
echo "  pixi run -e examples python $DIR/plot.py $OUT/laplacian.nc"
