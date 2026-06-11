#!/usr/bin/env bash
# Build and run every example under examples/ via its run.sh. An example may
# offer several build-system variants, each in its own subfolder with its own
# run.sh (e.g. laplacian/cmake/run.sh and laplacian/make/run.sh) — every run.sh
# found is built and run. Invoked by `pixi run test-examples` in the `examples`
# pixi env.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find every run.sh at any depth, pruning generated build/ trees so a stale
# artefact can never be mistaken for a driver. Sorted for deterministic order.
while IFS= read -r runsh; do
    echo "==> ${runsh%/run.sh}"
    bash "$runsh"
done < <(find "$DIR" -type d -name build -prune -o -type f -name run.sh -print | sort)
