#!/bin/bash
set -euo pipefail

# Only run in remote (web) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

PIXI_BIN="$HOME/.pixi/bin/pixi"

# Install pixi if not already present
if [ ! -x "$PIXI_BIN" ] && ! command -v pixi &>/dev/null; then
  curl -fsSL https://pixi.sh/install.sh | sh
fi

# Persist ~/.pixi/bin in PATH for the entire session so all hooks find pixi
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo 'export PATH="$HOME/.pixi/bin:$PATH"' >> "$CLAUDE_ENV_FILE"
fi

# Materialise the dev environment (conda + pypi deps)
cd "${CLAUDE_PROJECT_DIR:-$PWD}"
"$HOME/.pixi/bin/pixi" install
