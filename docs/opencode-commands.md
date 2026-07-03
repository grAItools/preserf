# Custom slash commands (opencode)

Lightweight, maintainer-defined slash commands usable in issue and PR comments,
built entirely from GitHub Actions workflow files on top of the
[opencode GitHub integration](https://opencode.ai/docs/github/). No servers, no
custom published actions. All comment parsing, model selection, and
acknowledgement live once in a reusable engine; a command is a tiny caller
workflow declaring a trigger word and a prompt template.

## For users

Invoke a command by starting a line of an issue or PR comment with the command
word:

```text
/review please look at the fused kernels
```

- **Pick a model** with `^shortcut` tokens anywhere in the comment. Multiple
  selectors fan out one opencode run per model:

  ```text
  /review ^large focus on correctness
  /review ^kimi ^glm compare approaches   # runs both, one run each
  /review just do it                      # no token -> the default model
  ```

  Currently defined shortcuts:

  | Shortcut   | Model                                         |
  | ---------- | --------------------------------------------- |
  | `^default` | `vars.OPENCODE_MODEL_DEFAULT` (repo variable) |
  | `^large`   | `vars.OPENCODE_MODEL_LARGE` (repo variable)   |
  | `^fast`    | `vars.OPENCODE_MODEL_FAST` (repo variable)    |
  | `^kimi`    | `cscs-inference/moonshotai/Kimi-K2.7-Code`    |
  | `^glm`     | `cscs-inference/zai-org/GLM-5.2`              |
  | `^glm4`    | `swiss-ai/zai-org/GLM-4.7-Flash`              |

  (The tier shortcuts resolve through repository variables — see below — so
  the resolved model can differ; an unset tier variable makes that shortcut
  unavailable.)

- **Reactions tell you what happened:**
  - 👀 (`eyes`) — the command was accepted and is running.
  - 😕 (`confused`) plus a short reply comment — a `^shortcut` was unknown; the
    reply lists the available shortcuts. The run does not start (a typo is not a
    failure); fix the token and comment again.

### Currently defined commands

| Command   | Where               | What it does                                                   |
| --------- | ------------------- | -------------------------------------------------------------- |
| `/agent`  | issue & PR comments | Forwards the request verbatim to opencode.                     |
| `/review` | PR comments only    | Focused code review of the pull request (correctness > style). |

## For maintainers

### Add a command

Copy [`.github/workflows/cmd-review.yml`](../.github/workflows/cmd-review.yml)
to `.github/workflows/cmd-<name>.yml` and change **two** occurrences of the
command word plus the prompt:

1. the `if:` prefilter — `contains(github.event.comment.body, '/<name>')`
   (a job-level `if:` cannot reference `with:` inputs, so it is separate), and
2. `with.command: <name>`,

then edit the `prompt:` template. Use `{{request}}` where the user's comment
(with the `/command` token and `^model` selectors stripped) should be spliced
in. `secrets: inherit` passes the provider keys through.

If the command is **PR-scoped** (like `/review`), keep the caller's PR-context
guard so it ignores comments on plain issues:
`github.event_name == 'pull_request_review_comment' || github.event.issue.pull_request != null`.
For a command that should also work on plain issues (like `/agent`), drop that
clause and keep just the `contains(...)` prefilter.

That caller file is the entire per-command surface area; everything else —
parsing, the model map, the 👀/😕 acknowledgement, the opencode invocation —
lives in [`opencode-cmd-engine.yml`](../.github/workflows/opencode-cmd-engine.yml).

### Where the model map lives

The shortcut → model mapping is the `MODEL_MAP` env block in the engine's
`parse` job. One `shortcut: full-model-spec` per line; a `default` entry is
mandatory. Values may reference repository/organization variables; a line
whose value resolves empty (unset variable) is dropped from the map:

```yaml
MODEL_MAP: |
  default: ${{ vars.OPENCODE_MODEL_DEFAULT }}
  large:   ${{ vars.OPENCODE_MODEL_LARGE }}
  fast:    ${{ vars.OPENCODE_MODEL_FAST }}
  kimi: cscs-inference/moonshotai/Kimi-K2.7-Code
  glm: cscs-inference/zai-org/GLM-5.2
  glm4: swiss-ai/zai-org/GLM-4.7-Flash
```

Set the `OPENCODE_MODEL_DEFAULT` / `_LARGE` / `_FAST` **repository variables**
(Settings → Secrets and variables → Actions → Variables) to (re)point a tier
without editing the workflow. `OPENCODE_MODEL_DEFAULT` must stay set: without
it a tokenless comment has no model, and the engine replies with a
"command misconfigured" error. Each model's **provider** must be declared in
[`opencode.json`](../opencode.json) and its API key present as a secret and
threaded through the engine's opencode step: `swiss-ai/*` → `SWISSAI_API_KEY`,
`cscs-inference/*` → `CSCS_INFERENCE_API_KEY`.
Those secrets are the same ones `opencode.yml` already uses.

### Naming constraints

- A command name must not be `oc` or `opencode`: the stock `opencode.yml` gate
  fires when `/oc` / `/opencode` is followed by a space or ends the comment
  (`endsWith(body, '/oc') || contains(body, '/oc ')`, and likewise for
  `/opencode`), so only an exact `/oc` / `/opencode` token co-triggers it. A
  name that merely starts with or contains `oc` (e.g. `/october`, `/blocklist`)
  is fine.
- Avoid command names that are prefixes of another command's name. The parser
  handles it correctly (word-boundary match), but both prefilters will briefly
  spin up runners.

### Security properties (preserve when refactoring)

- `github.event.comment.body` (and anything derived from it) is passed through
  `env:` only — never interpolated into a `run:` block via `${{ }}`.
- User-derived step outputs are written with a random-delimiter heredoc (see
  `emit()` in [`parse_opencode_cmd.py`](../.github/scripts/parse_opencode_cmd.py)),
  so comment content cannot forge additional outputs.
- All checkouts use `persist-credentials: false`; the opencode action manages
  its own credentials via OIDC (`id-token: write`).
- Permissions are minimal and job-scoped; each caller grants a superset of what
  the engine's jobs request.

### Restricting who can run a command

A command run inherits secrets and requests `id-token: write`, so an arbitrary
commenter must not be able to trigger it. This is gated **once, centrally** in
the engine (`opencode-cmd-engine.yml`): its `parse` job — which the `opencode`
job depends on — runs only for authorized commenters, so an unauthorized
comment skips the whole engine. Callers don't repeat the gate.

```yaml
# opencode-cmd-engine.yml, parse job
if: contains(fromJSON('["OWNER","MEMBER","COLLABORATOR"]'), github.event.comment.author_association)
```

This holds regardless of whether the opencode action also enforces commenter
permissions on its own (unverified here — see below); the gate is a
fail-secure default. To change who may run commands, edit this one list; it
applies to every command.

## Known assumptions / follow-ups

These need a real repo with the opencode app installed and cannot be verified
from the workflow files alone:

- That passing `prompt:` to the opencode action on an `issue_comment` event
  fully overrides its default comment-driven behavior.
- Whether the opencode action still enforces commenter permissions when given
  an explicit prompt (see the gate above).
