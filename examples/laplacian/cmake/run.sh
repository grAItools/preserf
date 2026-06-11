#!/usr/bin/env bash
# preserf example driver: preprocess -> build -> run.
#
# Run inside the `examples` pixi environment so `preserf`, `cmake`, and the
# Fortran/netcdf-fortran toolchain are all on PATH:
#
#   pixi run -e examples bash examples/laplacian/cmake/run.sh
#
# Produces:
#   build/laplacian.F90   expanded source (the !$SER directives made explicit)
#   build/laplacian       the compiled binary; run as `laplacian <outdir> [nsteps]`
#   out/laplacian.nc      the serialized store, one savepoint per time step
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$DIR/build"
OUT="$DIR/out"

mkdir -p "$OUT"

# A build/ left over from a different checkout location (e.g. the repo was
# moved or copied) carries a stale CMakeCache that makes reconfigure abort;
# drop it so re-runs from a relocated tree just work.
if [ -f "$BUILD/CMakeCache.txt" ]; then
    cached_src="$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$BUILD/CMakeCache.txt")"
    if [ "$cached_src" != "$DIR" ]; then
        echo "==> removing stale build cache (was configured for: $cached_src)"
        rm -rf "$BUILD"
    fi
fi

# 1. Configure + build. CMake expands the !$SER directives via the preserf CLI
#    (the generated build/laplacian.F90 is left in place to read), then
#    compiles it against the preserf_fortran helper.
echo "==> cmake: configuring (expands !\$SER) and building"
cmake -S "$DIR" -B "$BUILD"
cmake --build "$BUILD"

# 2. Run the binary; it writes the store into out/. Pass a second argument
#    (e.g. `"$BUILD/laplacian" "$OUT" 5`) to change the number of iterations.
echo "==> run: iterating the Laplacian and serializing each step"
"$BUILD/laplacian" "$OUT"

echo
echo "Store written to: $OUT/laplacian.nc"
echo "Verify and plot it with:"
echo "  pixi run -e examples python $DIR/../verify.py $OUT/laplacian.nc"
