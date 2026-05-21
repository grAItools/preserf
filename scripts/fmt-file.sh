#!/usr/bin/env bash
# fmt-file.sh — per-file formatter, invoked by the Claude Code
# PostToolUse hook after Write/Edit/MultiEdit with the edited file as $1.
# Keep this fast (<300ms); it runs on every save.

set -euo pipefail

file="${1:-}"
[[ -z "$file" ]] && { echo "usage: $0 <file>" >&2; exit 64; }

# Dispatch by extension. Silently skip anything we don't know how to format
# so the agent loop isn't spammed.
case "$file" in
  *.py)
    command -v pixi >/dev/null 2>&1 || exit 0
    pixi run -e dev ruff format "$file" >/dev/null 2>&1 || true
    ;;
esac
