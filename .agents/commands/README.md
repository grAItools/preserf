# Slash commands

Cross-tool slash command definitions live here. Each command is a single
Markdown file with YAML frontmatter (`description`, optional
`argument-hint`).

The same files are read by Claude Code (symlinked at `.claude/commands/`) and
OpenCode (symlinked at `.opencode/commands/`). The symlinks are created by the
post-generation hook; if you copy this layout manually — or are migrating a
brownfield repo where `.claude/commands/` and/or `.opencode/commands/` already
exist as real directories — move any local command files into
`.agents/commands/` first, then replace the old paths with symlinks:

```sh
# Run from the repo root. Removes the legacy dirs, so make sure any
# unique content has been copied into .agents/commands/ beforehand.
rm -rf .claude/commands .opencode/commands
ln -s ../.agents/commands .claude/commands
ln -s ../.agents/commands .opencode/commands
```

Authoring tips: keep each command short and imperative — the description is
what surfaces in the slash-command picker, and the body is the prompt the
agent will follow.
