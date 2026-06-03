#!/usr/bin/env bash
# Build and run every example under examples/ via its run.sh.
# Invoked by `pixi run test-examples` in the `examples` pixi env.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for d in "$DIR"/*/; do
    [ -f "$d/run.sh" ] || continue
    echo "==> $d"
    bash "$d/run.sh"
done
