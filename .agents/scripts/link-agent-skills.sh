#!/usr/bin/env bash
# Sync the canonical OpenSpec skills in .agents/skills/ to the per-harness
# skill directories as symlinks, following the agent-agnostic layout in
# .agents/AGENTS.md (skills are portable: identical across harnesses except
# for one invocation-spelling line, so the canonical generic copy wins).
#
#   link-agent-skills.sh          create/repair symlinks, prune stale ones
#   link-agent-skills.sh --check  exit 1 if the layout has drifted
#
# Run this after `openspec update` or `openspec init`, which rewrite the
# per-harness directories with real files.
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
declare -A valid_skills
for skill_dir in "$CANONICAL"/*/; do
    [ -d "$skill_dir" ] || continue
    valid_skills["$(basename "$skill_dir")"]=1
done

for target_dir in "${TARGETS[@]}"; do
    abs_target="$REPO_ROOT/$target_dir"
    mkdir -p "$abs_target"

    for name in "${!valid_skills[@]}"; do
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
        elif [ -e "$link_path" ]; then
            if $CHECK; then
                echo "DRIFT: $link_path exists as a real file/directory (expected symlink $link_target)" >&2
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

    # Prune stale symlinks whose target left the canonical dir.
    for link in "$abs_target"/*/; do
        link="${link%/}"
        [ -L "$link" ] || continue
        target="$(readlink "$link")"
        case "$target" in
            *"/.agents/skills/"*)
                name="$(basename "$link")"
                if [ -z "${valid_skills[$name]+x}" ]; then
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
