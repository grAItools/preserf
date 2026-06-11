#!/usr/bin/env bash
# Build and run every example under examples/ via its run.sh. An example may
# offer several build-system variants, each in its own subfolder with its own
# run.sh (e.g. laplacian/cmake/run.sh and laplacian/make/run.sh) — every run.sh
# found is built and run. Invoked by `pixi run test-examples` in the `examples`
# pixi env.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find every run.sh, pruning generated artefact trees (build/, out/, prefix/)
# so a stale file can never be mistaken for a driver. Capture first (not a
# process substitution) so a find failure aborts under `set -e` instead of
# silently running zero examples. Sorted for deterministic order.
runs="$(find "$DIR" \
    -type d \( -name build -o -name out -o -name prefix \) -prune -o \
    -type f -name run.sh -print | sort)"
while IFS= read -r runsh; do
    [ -n "$runsh" ] || continue
    echo "==> ${runsh%/run.sh}"
    bash "$runsh"
done <<< "$runs"
