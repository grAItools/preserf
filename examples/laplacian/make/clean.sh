#!/usr/bin/env bash
# Remove the install prefix, build, and serialized-store artifacts.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rm -rf "$DIR/build" "$DIR/out" "$DIR/prefix"
echo "cleaned $DIR/{build,out,prefix}"
