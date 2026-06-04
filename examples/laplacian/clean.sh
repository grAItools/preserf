#!/usr/bin/env bash
# Remove the build and serialized-store artifacts produced by run.sh.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rm -rf "$DIR/build" "$DIR/out"
echo "cleaned $DIR/{build,out}"
