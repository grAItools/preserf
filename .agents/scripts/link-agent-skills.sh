#!/usr/bin/env bash
# Sync the canonical OpenSpec skills in .agents/skills/ to the per-harness
# skill directories as symlinks, following the agent-agnostic layout in
# .agents/AGENTS.md (skills are portable: identical across harnesses except
# for one invocation-spelling line, so the canonical generic copy wins).
#
#   link-agent-skills.sh          create/repair symlinks, prune stale ones,
#                                convert generated duplicates to links
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

# The OpenSpec generator legitimately rewrites the canonical `/opsx:<cmd>`
# references per harness (see the CLI's utils/command-references.js):
# Claude keeps `/opsx:<cmd>`, Codex renders
# `$openspec-<skill> (Codex) or /openspec-<skill> (other agents)`, and
# OpenCode/OMP use `/opsx-<cmd>`. Every known spelling of one workflow
# normalizes to a per-command token (`NORM-<cmd>`), so a regenerated
# per-harness copy compares equal to the canonical copy, while two
# *different* workflows (e.g. verify vs archive) stay distinct and a
# hand-edited command reference still refuses conversion. Unknown
# references are left untouched, matching the CLI's own rewrite rule.
# Command/skill pairs mirror the CLI's COMMAND_TO_SKILL_NAME.
NORM_RULES=()
for pair in \
    "explore:openspec-explore" \
    "new:openspec-new-change" \
    "continue:openspec-continue-change" \
    "apply:openspec-apply-change" \
    "update:openspec-update-change" \
    "ff:openspec-ff-change" \
    "sync:openspec-sync-specs" \
    "archive:openspec-archive-change" \
    "bulk-archive:openspec-bulk-archive-change" \
    "verify:openspec-verify-change" \
    "onboard:openspec-onboard" \
    "propose:openspec-propose"
do
    cmd="${pair%%:*}"
    skill="${pair##*:}"
    NORM_RULES+=(
        "-e"
        's/\$'"${skill}"' \(Codex\) or \/'"${skill}"' \(other agents\)/NORM-'"${cmd}"'/g'
        "-e"
        's/\$'"${skill}"'/NORM-'"${cmd}"'/g'
        "-e"
        "s|/${skill}|NORM-${cmd}|g"
        "-e"
        "s|/opsx-${cmd}|NORM-${cmd}|g"
        "-e"
        "s|/opsx:${cmd}|NORM-${cmd}|g"
    )
done

drift=0

# Write a comparison snapshot of a skill directory to a file: a sorted
# inventory of regular files with their normalization-invariant content.
# Fails (nonzero, partial output only) when the directory contains any
# non-regular entry (symlinks etc.), or when any listing/read/normalize
# step fails — a failed snapshot must never count as a match.
snapshot_into() {
    local dir="$1" out="$2" listing tmp f
    : >"$out"
    if [ -n "$(find "$dir" -mindepth 1 ! -type f -print -quit)" ]; then
        echo "snapshot: $dir contains non-regular entries" >&2
        return 1
    fi
    listing="$(mktemp "${TMPDIR:-/tmp}/linkagent-listing.XXXXXX")" || return 1
    tmp="$(mktemp "${TMPDIR:-/tmp}/linkagent-content.XXXXXX")" || {
        rm -f "$listing"
        return 1
    }
    if ! (cd "$dir" && find . -type f | LC_ALL=C sort) >"$listing"; then
        rm -f "$listing" "$tmp"
        return 1
    fi
    while IFS= read -r f; do
        if ! { printf '=== %s\n' "$f"; tr -d '\r' <"$dir/$f"; } >"$tmp" 2>/dev/null; then
            rm -f "$listing" "$tmp"
            return 1
        fi
        if ! sed -E "${NORM_RULES[@]}" "$tmp" >>"$out"; then
            rm -f "$listing" "$tmp"
            return 1
        fi
    done <"$listing"
    rm -f "$listing" "$tmp"
    return 0
}

# Whether a regenerated per-harness directory duplicates the canonical
# skill modulo the known invocation spellings. Three outcomes:
#   0   equivalent — safe to convert to a symlink
#   1   not equivalent (genuine edit, different workflow, extra/missing
#       files, or non-regular entries) — refuse, keep the directory
#   2   snapshot failure — refuse, keep the directory, report the failure
generated_equivalent() {
    local dup="$1" canon="$2" snap_dup snap_canon rc
    snap_dup="$(mktemp "${TMPDIR:-/tmp}/linkagent-snap.XXXXXX")" || return 2
    snap_canon="$(mktemp "${TMPDIR:-/tmp}/linkagent-snap.XXXXXX")" || {
        rm -f "$snap_dup"
        return 2
    }
    if ! snapshot_into "$dup" "$snap_dup"; then
        rm -f "$snap_dup" "$snap_canon"
        return 2
    fi
    if ! snapshot_into "$canon" "$snap_canon"; then
        rm -f "$snap_dup" "$snap_canon"
        return 2
    fi
    if cmp -s "$snap_dup" "$snap_canon"; then
        rc=0
    else
        rc=1
    fi
    rm -f "$snap_dup" "$snap_canon"
    return "$rc"
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
            # only when it duplicates the canonical skill modulo the known
            # generator-controlled invocation spellings; anything else — a
            # genuine edit, a different workflow, extra entries — is
            # refused and never deleted.
            equivalence=0
            generated_equivalent "$link_path" "$skill_dir" || equivalence=$?
            if [ "$equivalence" -eq 0 ]; then
                if $CHECK; then
                    echo "DRIFT: $link_path is an unconverted duplicate of .agents/skills/$name" >&2
                    drift=1
                else
                    rm -r "$link_path"
                    ln -s "$link_target" "$link_path"
                    echo "Converted duplicate: $link_path -> $link_target"
                fi
            elif [ "$equivalence" -eq 2 ]; then
                echo "ERROR: could not compare $link_path with .agents/skills/$name (snapshot failure; nothing was deleted)." >&2
                exit 1
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
