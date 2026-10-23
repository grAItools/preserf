# Proposal

## Why

The GitHub issue and PR surfaces overlap the spec layer: three open
issues (#46, #47, #111) mirror work also tracked in
openspec/changes/, and six open PRs mix implementations with
ADR/deferral drafts that act as decisions outside the OpenSpec loop.
No single artifact owns a given problem's status, so the backlog is
hard to read and tracked follow-ups are indistinguishable from
abandoned PRs.

## What Changes

- Document an issue-driven change lifecycle: GitHub issues are the user
  entry point (bug reports and feature requests, problems not
  solutions); a human acceptance gate (triage/accepted) precedes spec
  work; accepted issues link bidirectionally to a named OpenSpec
  change; issues close automatically when the implementing change
  merges (Closes #N)
- Add bug and feature issue templates under .github/ISSUE_TEMPLATE/
- Record the decision as dev/adr/0013 (0012 is reserved by the
  in-flight improve-store-efficiency compression ADR)

## Out of Scope

- Migration of the existing issue/PR backlog (separate per-item
  follow-up)
- Changes to the OpenSpec propose/apply/archive loop itself
- Automation of the acceptance gate (bots, workflows)

## Capabilities

None — process-only documentation change; no capability delta (the
--skip-specs carve-out for pure infrastructure changes applies).

## Impact

AGENTS.md, openspec/config.yaml (context block), docs/README.md,
.github/ISSUE_TEMPLATE/, CHANGELOG.md, dev/adr/0013.
