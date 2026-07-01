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
6. Set the model configuration the default table reads (see
   [Selecting the model(s)](#selecting-the-models)):
   - **Variables** `REPO_AGENT_MODEL_DEFAULT` / `_SMALL` / `_LARGE` = the
     opencode model ids for those tiers.
   - **Secrets** for each provider you enable: `OPENCODE_API_KEY`
     (`opencode-go/*`), `SWISSAI_API_KEY` (`swiss-ai/*`), `CSCS_INFERENCE_API_KEY`
     (`cscs-inference/*`). `OPENCODE_API_KEY` is the same engine secret
     `opencode.yml` already uses.

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

The invoker picks which model runs by adding `^<name>` tokens to the mention;
this is handled once in `agent.yml`, so callers get it for free.

```text
@repo-agent ^small refactor this function
@repo-agent ^cscs:glm ^sai:glm4 compare approaches   # runs both, one parallel run each
@repo-agent just do it                                 # no token -> the default model
```

The menu is the `models` input — a YAML table defined once in `agent.yml`
(`name` = the `^token`, `model` = the opencode id, `default: true` = what runs
with no token). The default table pairs three repo-variable-driven tiers with
provider-pinned entries:

```yaml
models: |
  - name: default
    model: ${{ vars.REPO_AGENT_MODEL_DEFAULT }}
    default: true
  - name: small
    model: ${{ vars.REPO_AGENT_MODEL_SMALL }}
  - name: large
    model: ${{ vars.REPO_AGENT_MODEL_LARGE }}
  - name: cscs:glm
    model: cscs-inference/zai-org/GLM-5.2
  - name: cscs:kimi
    model: cscs-inference/moonshotai/Kimi-K2.7-Code
  - name: sai:glm4
    model: swiss-ai/zai-org/GLM-4.7-Flash
```

Callers only pass `models:` to change the menu. The `^<name>` tokens are
stripped from the text the agent sees, and each selected model runs as an
independent parallel job (`fail-fast: false`), so one model failing doesn't
cancel the others. Keep a `default: true` entry, or a tokenless mention selects
nothing and no run starts.

> **Every model in the table must be backed by real configuration**, or the
> run fails:
>
> - The `default` / `small` / `large` tiers read their ids from the repository
>   variables `REPO_AGENT_MODEL_DEFAULT` / `_SMALL` / `_LARGE` — set these under
>   **Settings → Secrets and variables → Actions → Variables**. (The workflow
>   fails fast with a clear message if a selected tier resolves to an empty id.)
> - Each `model` id's **provider** must be declared in [`opencode.json`](../opencode.json)
>   with its API-key env var, and that key must be present as a secret and
>   threaded through `agent-runtime`: `opencode-go/*` → `OPENCODE_API_KEY`,
>   `swiss-ai/*` → `SWISSAI_API_KEY`, `cscs-inference/*` → `CSCS_INFERENCE_API_KEY`.
>
> Adding a new provider-backed model means updating **both** `opencode.json`
> (provider + model) and, for a new key, the secret wiring in `agent.yml` and
> `agent-runtime/action.yml`.

> Running several models against the same PR means several agents push in
> parallel. That's ideal for question-answering or when each opens its own
> branch/PR; for in-place edits to one branch, prefer a single `^model`.

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
