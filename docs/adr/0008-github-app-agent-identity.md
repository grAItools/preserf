# 8. Mention-triggered agents run under a GitHub App identity

## Status

Accepted

## Context

The repo already runs agentic workflows (`opencode.yml`, the gh-aw
`grumpy-reviewer`, `agentics-maintenance`), but each one re-declares its
trigger gating, checkout, auth, and engine wiring. We want a Copilot-style
flow where mentioning a handle (`@repo-agent`) in an issue or PR comment
dispatches an agent that can do work and commit/push/open PRs — and we want
adding a _new_ such agent to cost only a prompt and a trigger, not a copy of
all that infrastructure.

Two questions drive the decision:

1. **What identity does the agent act under?** The default `GITHUB_TOKEN`
   posts and commits as `github-actions[bot]`, which is shared across every
   workflow and not mentionable. A dedicated identity gives the agent a
   coherent, attributable presence.
2. **How is the shared setup packaged?** GitHub Actions offers composite
   actions (reusable _steps_) and reusable workflows (reusable _jobs_,
   `on: workflow_call`); triggers (`on:`) can live in neither and must stay in
   each caller.

A GitHub App is a new authentication dependency (per AGENTS.md, that warrants
an ADR). The alternative — a machine-user account with a PAT — is assignable
to issues but consumes a seat, carries a long-lived broad-blast-radius token,
and must be re-shared per repo. Issue _assignment_ is not a requirement here;
mention-triggering is.

## Decision

**Register a GitHub App (`repo-agent[bot]`) and run mention-triggered
agents under its short-lived installation token.** The App is granted
Contents + Issues + Pull requests = Read & write, so the agent can commit,
push, open/close issues, and open/merge PRs — all attributed to the bot.
Credentials live as `vars.REPO_AGENT_APP_ID` and
`secrets.REPO_AGENT_APP_KEY`.

**Package the shared setup as a composite action plus a reusable workflow:**

- `.github/actions/agent-runtime/action.yml` mints the installation token,
  resolves the bot's git identity (the `<uid>+<slug>[bot]@users.noreply…`
  committer email so commits show the bot avatar), checks out as the bot, and
  runs the **existing opencode engine** (no new agent runtime, reusing
  `OPENCODE_API_KEY`).
- `.github/workflows/agent.yml` (`workflow_call`) wraps the mention plumbing —
  loop guard (`sender.type != 'Bot'`), word-boundary mention parse, and an
  `author_association` gate that runs _before_ any PR-head checkout — and calls
  the composite action with the composed prompt.

A new agent is then a ~15-line caller (`agent-mention.yml` is the template):
its own `on:` block plus `uses: ./.github/workflows/agent.yml` with a
`base-prompt`.

## Consequences

- **Positive.** Installation tokens are short-lived (~1h) and scoped per
  install — small blast radius, no seat, no rotation chore. Every agent action
  is attributed to one coherent `repo-agent[bot]` identity. New agents cost
  a prompt + trigger; the App/checkout/auth/engine wiring exists once.
- **Negative / constraints.**
  - One-time manual setup (register App, set permissions, install, store
    secret/var) that cannot be automated from this repo — documented in
    `docs/agent-workflows.md`.
  - The App **cannot be assigned to issues** and **cannot approve its own
    PRs**; its merges are still subject to branch protection. If
    issue-assignment semantics are later required, that needs a machine user —
    supersede this ADR.
  - The App token (unlike `GITHUB_TOKEN`) **triggers other workflows** on push,
    a fresh recursion vector — hence the loop guard in every caller path.
- **Revisiting.** Supersede if the identity mechanism changes (e.g. moving to a
  machine user for assignment) or if the engine is swapped from opencode.
