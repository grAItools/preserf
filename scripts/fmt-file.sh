#!/usr/bin/env bash
# fmt-file.sh — per-file formatter, invoked by the Claude Code
# PostToolUse hook after Write/Edit/MultiEdit with the edited file as $1.
# Keep this fast (<300ms); it runs on every save.
#
# TODO: replace the no-op below with your project's per-file formatter.
# Examples:
#   uv run ruff format "$1"
#   pnpm exec prettier --write "$1"
#   gofmt -w "$1"
#   cargo fmt -- "$1"

set -euo pipefail

file="${1:-}"
[[ -z "$file" ]] && { echo "usage: $0 <file>" >&2; exit 64; }

# Placeholder: silent no-op. This runs on every Write/Edit/MultiEdit
# via the Claude Code PostToolUse hook, so a verbose default would
# spam the agent loop. Replace with your formatter (see TODO above).
exit 0
