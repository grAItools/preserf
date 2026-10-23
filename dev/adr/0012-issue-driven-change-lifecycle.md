# 12. Issue-driven change lifecycle: GitHub issues link to OpenSpec changes

## Status

Accepted

## Context

ADR 0010 adopted OpenSpec as the spec-driven layer, but the GitHub
issue and PR surface kept growing in parallel: open issues mirror
work also tracked in `openspec/changes/`, open PRs mix
implementations with ADR/deferral drafts that act as decisions
outside the spec layer, and deliberation on a single question can
produce competing ADR drafts with no resolution vehicle. No single
artifact owns a given problem's status, so the backlog is hard to
read, work lands twice, and a tracked follow-up is indistinguishable
from an abandoned PR.

## Decision

- GitHub issues are the sole user-facing entry point: bug reports and
  feature requests. Issues describe _problems_; solution sketches are
  welcome input, but the change spec owns the design.
- A human developer is the acceptance gate. An issue is marked
  `triage/accepted` when valid and `triage/declined` otherwise; agents
  may summarize or draft but never self-accept.
- An accepted issue is dealt with by drafting an OpenSpec change whose
  proposal references the issue (`Issue: #N`), and the change name is
  posted as a comment on the issue so the link is bidirectional.
- An issue closes when the implementing change merges: the PR carries
  `Closes #N`, and GitHub closes the issue automatically at merge.
- Accepted issues blocked on an external enabler carry
  `blocked/deferred`, stay open, and document the blocker in the linked
  proposal — deferral is a labelled state, not an open PR carrying an
  ADR.
- Spec-first work (not originating from an issue) skips the acceptance
  gate but runs the same propose → apply → archive loop.

## Consequences

- Each problem has one named owner artifact; the issue thread and the
  change proposal reference each other by name.
- PRs stop being decision carriers: decisions land as ADRs in
  `dev/adr/` as part of the change, referenced from the proposal, and
  implementation PRs reference the change.
- The acceptance gate is a human action (applying a label), keeping
  agent-generated traffic from consuming spec-layer effort.
- Deferral becomes visible and reversible: a `blocked/deferred` label
  plus a documented blocker replaces zombie issues and ADR-PRs.
- Migrating the existing backlog is a separate follow-up (per-item
  disposition), not part of this decision.
