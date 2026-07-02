# Mention-triggered agent workflows

A Copilot-style handle — `@repo-agent` — that, when mentioned in an issue or
PR comment, dispatches a coding agent running under a dedicated GitHub-App
identity. The shared infrastructure (App token, bot identity, checkout, auth
gate, opencode engine) lives in two reusable pieces, so adding a new agent
costs only a prompt and a trigger.

See [ADR 0008](adr/0008-github-app-agent-identity.md) for the why.

## Pieces

| File                                              | Role                                                                                                                                                                                             |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `.github/actions/agent-runtime/action.yml`        | Composite action: mint App token → resolve bot git identity → checkout as bot → run opencode with the prompt.                                                                                    |
| `.github/workflows/repo-agent.yml`                | Reusable workflow (`workflow_call`): mention parse, loop guard, `author_association` gate; calls the composite action.                                                                           |
| `.github/workflows/repo-agent-actions.yml`        | Caller for issue/PR agents (the general `@repo-agent`); the copy-me template.                                                                                                                    |
| `.github/workflows/repo-agent-pr-actions.yml`     | Caller for PR-only agents — bundles the mirrored high-effort reviewers `@repo-reviewer` (keeps project context) and `@external-reviewer` (drops it), which post threaded inline review comments. |
| `.github/workflows/repo-agent--issue-actions.yml` | Caller for automatic issue agents (no mention) — bundles `@repo-triager`, which triages, labels, and summarizes new issues.                                                                      |

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

Copy `repo-agent-actions.yml`, rename it, and change three things:

```yaml
name: docs-agent
on:
  issue_comment:
    types: [created] # not `edited` — an edit would re-run the whole agent
permissions:
  id-token: write # opencode OIDC (reusable-workflow perms can only be reduced,
  contents: read #  not elevated — so grant everything repo-agent.yml needs here)
  pull-requests: read # the select job resolves the PR head SHA via the API
jobs:
  agent:
    uses: ./.github/workflows/repo-agent.yml
    with:
      trigger-phrase: "@preserf-docs"
      base-prompt: |
        You are the preserf docs agent. When mentioned, update documentation
        under docs/ to match the request, run `pixi run verify`, then open a PR.
    secrets: inherit
```

Grant the caller `id-token: write` + `contents: read`, plus `pull-requests: read`
whenever the agent can run in PR context (issue comments on PRs, review
comments). Reusable-workflow token permissions can only be **reduced**, not
elevated, by the callee, so a caller that grants only `contents: read` starves
the reusable workflow: opencode's OIDC (`id-token`) is dropped and the `select`
job can't resolve the PR head SHA (it falls back to the default branch). An
issue-only caller can omit `pull-requests: read`.

The user's text after the trigger phrase (with any `^model` tokens removed) is
appended to `base-prompt` under a `## Request` heading and handed to the agent.
A **mention-only** trigger with no text after it — e.g. a fixed-purpose agent
invoked with just `@repo-agent` — sends the `base-prompt` alone, with no empty
`## Request` section, so agents that need no per-invocation prompt get a clean
input. `secrets: inherit` passes `OPENCODE_API_KEY` / `REPO_AGENT_APP_KEY` /
`SWISSAI_API_KEY` through; `REPO_AGENT_APP_ID` is read from repo variables.

Optional `with:` inputs: `models` (the selection table, see below), `runs-on`
(default `ubuntu-latest`), `allowed-associations` (default
`OWNER,MEMBER,COLLABORATOR`), `require-mention` (default `true`),
`drop-project-context` (default `false`), `timeout-minutes` (default `30`; hard
wall-clock cap on the agent job so a hung engine can't hold a runner and its
concurrency slot), and `permission-contents` / `permission-issues` /
`permission-pull-requests` (default empty = the App token inherits the
installation's full grant; set e.g. `read` to scope the minted token down for an
agent that never pushes — see [Security model](#security-model)).

Set `require-mention: false` for an **automatic** agent that fires on the event
itself rather than a mention — e.g. `repo-agent--issue-actions.yml` triages
every opened issue. In that mode the mention gate and the `author_association`
gate are skipped, the command is empty (so the agent gets the `base-prompt`
alone), and the prompt should read the triggering payload from
`$GITHUB_EVENT_PATH` and treat its user content as untrusted data.

Set `drop-project-context: true` when the agent checks out an arbitrary or
untrusted ref (e.g. a PR under review): `agent-runtime` then replaces the
checked-out ref's opencode config (`.opencode/` and root `opencode.json`) with
the trusted default-branch version before running opencode. This does two
things at once — it neutralizes any hostile config the reviewed ref might carry
(opencode *executes* `formatter` and local `mcp` server commands, and any
`.opencode/plugin|tool` code, at startup, so a planted one would otherwise run
under the App token before the agent does anything), and it keeps a valid
providers config so a ref whose opencode config is malformed can't abort the
run. The default `false` keeps the checked-out ref's project context intact. The
bundled `@external-reviewer` sets this; its mirror `@repo-reviewer` and the
general `@repo-agent` keep the context.

> The caller must define its own `on:` triggers — a reusable workflow cannot
> declare them for the caller. The workflow file must also be on the **default
> branch** before comment events will run it.

## Selecting the model(s)

The invoker picks which model runs by adding `^<name>` tokens to the mention;
this is handled once in `repo-agent.yml`, so callers get it for free.

```text
@repo-agent ^small refactor this function
@repo-agent ^cscs:glm ^sai:glm4 compare approaches   # runs both, one parallel run each
@repo-agent just do it                                 # no token -> the default model
```

The menu is the `models` input — a YAML table defined once in `repo-agent.yml`
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
> (provider + model) and, for a new key, the secret wiring in `repo-agent.yml` and
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
- **Boundary match.** The mention must start the line or follow whitespace and
  must not be followed by a word character or hyphen, so neither an embedded
  `foo@repo-agent` nor a longer handle like `@repo-agent-staging` fires it.
- **Scoped, short-lived token.** The installation token expires (~1h) and is
  scoped to the install; it is never written to logs. By default it carries the
  App installation's full grant (Contents + Issues + Pull requests, read/write).
  For an agent that runs on **untrusted input without a mention gate** — the
  automatic `@repo-triager` fires on every opened issue — scope the token down
  with the `permission-*` inputs (the triager sets `permission-contents: read`,
  `permission-issues: write`), so a successful prompt injection can't push code
  or open PRs, only what the agent legitimately needs.
- **Untrusted reviewed config.** For agents that check out an untrusted ref,
  `drop-project-context: true` restores the trusted default-branch opencode
  config so a hostile head can't run code at opencode startup (see
  [Add a new agent](#add-a-new-agent)).

## Concurrency

Runs are grouped by `(agent, issue/PR)` — `agent-<trigger-phrase>-<number>`.
So the **same** agent triggered more than once on one issue/PR is serialized
(one run at a time, regardless of which comment triggered it), while
**different** agents on the same issue/PR run in parallel. `cancel-in-progress`
is off, so a second trigger of the same agent queues behind the first rather
than killing an in-flight commit/push.

> By default (`queue: single`) GitHub keeps at most one running + one pending
> run per group, so if the same agent is triggered 3+ times on one issue in
> quick succession, the middle pending run is dropped (only the running one and
> the newest are kept). To keep the intermediate triggers, set
> `concurrency.queue: max` (up to 100 pending, FIFO — not combinable with
> `cancel-in-progress`). For ordering several _different_ agents in one run,
> chain the caller jobs with `needs:` instead.
