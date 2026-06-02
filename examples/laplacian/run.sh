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

mkdir -p "$OUT"

# 1. Configure + build. CMake expands the !$SER directives via the preserf CLI
#    (the generated build/laplacian.F90 is left in place to read), then
#    compiles it against the preserf_fortran helper.
echo "==> cmake: configuring (expands !\$SER) and building"
cmake -S "$DIR" -B "$BUILD"
cmake --build "$BUILD"

# 2. Run the binary; it writes the store into out/.
echo "==> run: computing Laplacian and serializing"
"$BUILD/laplacian" "$OUT"

echo
echo "Store written to: $OUT/laplacian.nc"
echo "Plot it with:"
echo "  pixi run -e examples python $DIR/plot.py $OUT/laplacian.nc"
