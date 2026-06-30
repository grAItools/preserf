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

Optional `with:` inputs: `model` (default `opencode-go/glm-5.2`), `runs-on`
(default `ubuntu-latest`), `allowed-associations` (default
`OWNER,MEMBER,COLLABORATOR`).

> The caller must define its own `on:` triggers — a reusable workflow cannot
> declare them for the caller. The workflow file must also be on the **default
> branch** before comment events will run it.

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
