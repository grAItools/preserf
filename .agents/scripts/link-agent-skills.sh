#!/usr/bin/env bash
# Sync the canonical OpenSpec skills in .agents/skills/ to the per-harness
# skill directories as symlinks, following the agent-agnostic layout in
# .agents/AGENTS.md (skills are portable: identical across harnesses except
# for one invocation-spelling line, so the canonical generic copy wins).
#
#   link-agent-skills.sh          create/repair symlinks, prune stale ones,
#                                convert byte-identical duplicates to links
#   link-agent-skills.sh --check  exit 1 if the layout has drifted
#
# Written for bash 3.2 (macOS ships it) — no associative arrays.
#
# Run this after `openspec update` or `openspec init`, which rewrite the
# per-harness directories.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CANONICAL="$REPO_ROOT/.agents/skills"
TARGETS=(".claude/skills" ".opencode/skills" ".omp/skills")
CHECK=false
[ "${1:-}" = "--check" ] && CHECK=true

if [ ! -d "$CANONICAL" ]; then
    echo "ERROR: canonical skills dir $CANONICAL not found." >&2
    exit 1
fi

drift=0

# The OpenSpec generator legitimately rewrites the canonical `/opsx:<cmd>`
# references per harness (see the CLI's utils/command-references.js):
# Claude keeps `/opsx:<cmd>`, Codex renders
# `$openspec-<skill> (Codex) or /openspec-<skill> (other agents)`, and
# OpenCode/OMP use `/opsx-<cmd>`. Normalizing every known spelling to one
# token lets a freshly generated per-harness copy compare equal to the
# canonical copy; any difference beyond those spellings (a genuine edit)
# still differs and is refused.
normalized_snapshot() {
    (cd "$1" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
        printf '=== %s\n' "$f"
        tr -d '\r' <"$f" | sed -E \
            -e 's/\$openspec-[a-z0-9-]+ \(Codex\) or \/openspec-[a-z0-9-]+ \(other agents\)/INVOC/g' \
            -e 's|/opsx:[a-z-]+|INVOC|g' \
            -e 's|/opsx-[a-z-]+|INVOC|g' \
            -e 's/\$openspec-[a-z0-9-]+/INVOC/g' \
            -e 's|/openspec-[a-z0-9-]+|INVOC|g'
    done)
}

for target_dir in "${TARGETS[@]}"; do
    abs_target="$REPO_ROOT/$target_dir"
    if $CHECK; then
        if [ ! -d "$abs_target" ]; then
            echo "DRIFT: $abs_target missing (expected per-harness skill dir)" >&2
            drift=1
            continue
        fi
    else
        mkdir -p "$abs_target"
    fi

    for skill_dir in "$CANONICAL"/*/; do
        [ -d "$skill_dir" ] || continue
        name="$(basename "$skill_dir")"
        link_path="$abs_target/$name"
        link_target="../../.agents/skills/$name"

        if [ -L "$link_path" ]; then
            if [ "$(readlink "$link_path")" = "$link_target" ]; then
                continue
            fi
            if $CHECK; then
                echo "DRIFT: $link_path -> $(readlink "$link_path") (expected $link_target)" >&2
                drift=1
            else
                rm "$link_path"
                ln -s "$link_target" "$link_path"
                echo "Relinked: $link_path -> $link_target"
            fi
        elif [ -d "$link_path" ]; then
            # A real directory where the canonical skill already exists is
            # the expected state right after `openspec init`/`openspec update`
            # regenerated the harness files. Convert it back to a symlink
            # when it differs from the canonical skill only in the known
            # generator-controlled invocation spellings (or not at all);
            # any other difference is a hand-edited or divergent copy,
            # which is never deleted automatically.
            if cmp -s <(normalized_snapshot "$link_path") \
                     <(normalized_snapshot "$skill_dir"); then
                if $CHECK; then
                    echo "DRIFT: $link_path is an unconverted duplicate of .agents/skills/$name" >&2
                    drift=1
                else
                    rm -r "$link_path"
                    ln -s "$link_target" "$link_path"
                    echo "Converted duplicate: $link_path -> $link_target"
                fi
            else
                echo "ERROR: $link_path differs from .agents/skills/$name beyond the known per-harness invocation spellings." >&2
                echo "       Reconcile manually (delete it after salvaging any edits), then re-run this script." >&2
                exit 1
            fi
        elif [ -e "$link_path" ]; then
            if $CHECK; then
                echo "DRIFT: $link_path exists as a real file (expected symlink $link_target)" >&2
                drift=1
            else
                echo "ERROR: $link_path exists but is not a symlink; refusing to delete." >&2
                exit 1
            fi
        else
            if $CHECK; then
                echo "DRIFT: $link_path missing (expected symlink $link_target)" >&2
                drift=1
            else
                ln -s "$link_target" "$link_path"
                echo "Linked: $link_path -> $link_target"
            fi
        fi
    done

    # Prune stale symlinks whose canonical skill no longer exists. Enumerate
    # without a trailing slash so dangling symlinks (whose target directory
    # is gone) are matched too.
    for link in "$abs_target"/*; do
        [ -L "$link" ] || continue
        target="$(readlink "$link")"
        case "$target" in
            *"/.agents/skills/"*)
                name="$(basename "$link")"
                if [ ! -d "$CANONICAL/$name" ]; then
                    if $CHECK; then
                        echo "DRIFT: stale symlink $link (no canonical skill $name)" >&2
                        drift=1
                    else
                        rm "$link"
                        echo "Pruned: $link"
                    fi
                fi
                ;;
        esac
    done
done

if $CHECK; then
    if [ "$drift" -ne 0 ]; then
        echo "FAIL: agent skill layout has drifted; run .agents/scripts/link-agent-skills.sh" >&2
        exit 1
    fi
    echo "OK: agent skill layout is in sync (canonical: .agents/skills/)"
fi
