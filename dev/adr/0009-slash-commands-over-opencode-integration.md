# 9. Custom slash commands over the opencode GitHub integration

## Status

Accepted (supersedes ADR 0008)

## Context

[ADR 0008](0008-github-app-agent-identity.md) introduced mention-triggered
agents (`@repo-agent` and friends) running under a dedicated GitHub-App
identity, packaged as a composite action (`agent-runtime`) plus a reusable
workflow (`repo-agent.yml`) with several callers. That machinery carried real
weight: a GitHub App to register, install, and rotate; App-token minting and bot
git-identity resolution; a `pull_request_target`-style auth gate that had to run
before any PR-head checkout; and project-context stripping to survive untrusted
refs. It also let the agent commit, push, and open PRs under the bot — a broad
capability surface for what, in practice, we mostly wanted: on-demand
comment-triggered assistance (review, ad-hoc questions).

The repo already runs the stock opencode workflow (`opencode.yml`), which the
opencode GitHub app drives directly. Building command triggers on that same
integration removes the need for a second identity and its custom action, at the
cost of the write-as-a-bot attribution that ADR 0008 provided.

## Decision

**Replace the `@repo-agent` GitHub-App machinery with a lightweight
slash-command framework built entirely on the opencode GitHub integration.**

Removed: `.github/actions/agent-runtime/`, `.github/workflows/repo-agent.yml`,
`repo-agent-actions.yml`, `repo-agent-pr-actions.yml`,
`repo-agent--issue-actions.yml`, and `docs/agent-workflows.md`.

Added:

- `.github/workflows/opencode-cmd-engine.yml` — a reusable engine
  (`workflow_call`) that centralizes comment parsing, the `^shortcut` model
  map, the 👀/😕 acknowledgement, and the opencode invocation (fanning out one
  matrix job per selected model).
- `.github/scripts/parse_opencode_cmd.py` — stdlib-only, unit-tested parsing
  logic (trigger word-boundary match, `^model` selection, request cleaning,
  `{{request}}` substitution), covered by
  `tests/unit_tests/test_parse_opencode_cmd.py`.
- `.github/workflows/cmd-review.yml` — the example `/review` command and the
  copy-me template; a new command is a tiny caller declaring a trigger word and
  a prompt.

Security properties are preserved from the reference design: untrusted comment
text flows through `env:` only (never into `run:` via `${{ }}`), user-derived
step outputs use random-delimiter heredocs so content cannot forge outputs,
checkouts set `persist-credentials: false`, and permissions stay minimal and
job-scoped. Model tiers read `OPENCODE_MODEL_*` repository variables with
fallbacks to the repo's opencode providers (`opencode.json`), keyed on the same
`OPENCODE_API_KEY` / `SWISSAI_API_KEY` / `CSCS_INFERENCE_API_KEY` secrets
`opencode.yml` already uses. Documented in `docs/opencode-commands.md`.

## Consequences

- **Positive.** No GitHub App to register, install, or rotate; no custom
  composite action to maintain. Adding a command is one small caller file. The
  parser is plain Python with real unit tests, so the trickiest logic is
  verifiable off-CI. The capability surface shrinks to what opencode grants.
- **Negative / constraints.**
  - We give up the coherent `repo-agent[bot]` write identity from ADR 0008;
    actions are attributed to whatever identity the opencode integration uses,
    and the App-token commit/push/open-PR affordance is gone. Reinstating
    branded-bot identity would need the optional `create-github-app-token` +
    opencode `token:` follow-up noted in `docs/opencode-commands.md`.
  - Two assumptions remain unverified until exercised on a live repo with the
    opencode app installed: that an explicit `prompt:` fully overrides the
    action's default comment behavior, and whether it still enforces commenter
    permissions (if not, add the `author_association` gate documented in
    `docs/opencode-commands.md`).
- **Revisiting.** Supersede if we again need write-as-a-bot attribution or
  issue-assignment semantics, or if the engine is swapped away from opencode.
