# Mention-triggered agent workflows

A Copilot-style handle — `@repo-agent` — that, when mentioned in an issue or
PR comment, dispatches a coding agent running under a dedicated GitHub-App
identity. The shared infrastructure (App token, bot identity, checkout, auth
gate, opencode engine) lives in two reusable pieces, so adding a new agent
costs only a prompt and a trigger.

See [ADR 0008](adr/0008-github-app-agent-identity.md) for the why.

## Pieces

| File                                       | Role                                                                                                                   |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| `.github/actions/agent-runtime/action.yml` | Composite action: mint App token → resolve bot git identity → checkout as bot → run opencode with the prompt.          |
| `.github/workflows/agent.yml`              | Reusable workflow (`workflow_call`): mention parse, loop guard, `author_association` gate; calls the composite action. |
| `.github/workflows/agent-mention.yml`      | Example caller / copy-me template.                                                                                     |

## One-time setup (manual)

The GitHub App must be registered by an org/repo admin — it cannot be created
from CI.

1. **Org settings → Developer settings → GitHub Apps → New GitHub App.** Name
   it `Repo Agent` (this fixes the handle `repo-agent[bot]`). **Homepage URL**
   is required but unused by this flow — set it to the repository URL
   (`https://github.com/grAItools/preserf`). Under **Webhook**, uncheck
   **Active** (Actions drives it, not webhooks).
2. **Permissions → Repository:** Contents = Read & write, Issues = Read &
   write, Pull requests = Read & write.
3. **Create**, then **Generate a private key** (downloads a `.pem`).
4. **Install** the App on the repo (or the whole org).
5. Store the credentials on the repo (or org):
   - **Variable** `REPO_AGENT_APP_ID` = the App ID.
   - **Secret** `REPO_AGENT_APP_KEY` = the full `.pem` contents.

`OPENCODE_API_KEY` (and optionally `SWISSAI_API_KEY`) are the same engine
secrets `opencode.yml` already uses.

## Add a new agent

Copy `agent-mention.yml`, rename it, and change three things:

```yaml
name: docs-agent
on:
  issue_comment:
    types: [created, edited]
permissions:
  contents: read
jobs:
  agent:
    uses: ./.github/workflows/agent.yml
    with:
      trigger-phrase: "@preserf-docs"
      base-prompt: |
        You are the preserf docs agent. When mentioned, update documentation
        under docs/ to match the request, run `pixi run verify`, then open a PR.
    secrets: inherit
```

The user's text after the trigger phrase is appended to `base-prompt` under a
`## Request` heading and handed to the agent. `secrets: inherit` passes
`OPENCODE_API_KEY` / `REPO_AGENT_APP_KEY` / `SWISSAI_API_KEY` through;
`REPO_AGENT_APP_ID` is read from repo variables.

Optional `with:` inputs: `models` (the selection table, see below), `runs-on`
(default `ubuntu-latest`), `allowed-associations` (default
`OWNER,MEMBER,COLLABORATOR`).

> The caller must define its own `on:` triggers — a reusable workflow cannot
> declare them for the caller. The workflow file must also be on the **default
> branch** before comment events will run it.

## Selecting the model(s)

The invoker picks which model runs by adding `+<name>` tokens to the mention;
this is handled once in `agent.yml`, so callers get it for free.

```text
@repo-agent +kimi refactor this function
@repo-agent +glm +kimi compare approaches   # runs both, one parallel run each
@repo-agent just do it                        # no token -> the default model
```

The menu is the `models` input — a YAML table defined once in `agent.yml`,
mirroring `opencode.yml`'s table (`name` = the `+token`, `model` = the opencode
id, `default: true` = what runs with no token):

```yaml
models: |
  - name: glm
    model: opencode-go/glm-5.2
    default: true
  - name: kimi
    model: opencode-go/kimi-k2.6
  - name: deepseek
    model: opencode-go/deepseek-v4-pro
  - name: qwen
    model: opencode-go/qwen3.6-plus
```

Callers only pass `models:` to change the menu (e.g. add a `swiss-ai/*` model,
which reads `SWISSAI_API_KEY`). The `+<name>` tokens are stripped from the text
the agent sees, and each selected model runs as an independent parallel job
(`fail-fast: false`), so one model failing doesn't cancel the others. Keep a
`default: true` entry, or a tokenless mention selects nothing and no run starts.

> Running several models against the same PR means several agents push in
> parallel. That's ideal for question-answering or when each opens its own
> branch/PR; for in-place edits to one branch, prefer a single `+model`.

## Security model

- **Loop guard.** The job `if:` skips `sender.type == 'Bot'`, so the bot's own
  comments (which may echo the handle) don't re-trigger it. The App token
  triggers other workflows on push, so keep this guard in any new caller.
- **Auth gate.** `author_association` must be in `allowed-associations`, checked
  **before** any PR-head checkout — so an untrusted fork PR's code is never run
  under the privileged App token (the `pull_request_target`-style footgun).
- **Word-boundary match.** `@repo-agent` is matched with a `\b` boundary, so
  `@repo-agent-staging` does not fire it.
- **Scoped, short-lived token.** The installation token expires (~1h) and is
  scoped to the install; it is never written to logs.
