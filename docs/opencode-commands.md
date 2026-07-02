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
  /review ^fast ^large compare approaches   # runs both, one run each
  /review just do it                        # no token -> the default model
  ```

  Currently defined shortcuts:

  | Shortcut   | Model (default fallback)        |
  | ---------- | ------------------------------- |
  | `^default` | `opencode-go/glm-5.2`           |
  | `^large`   | `cscs-inference/zai-org/GLM-5.2` |
  | `^fast`    | `opencode-go/kimi-k2.6`         |

  (A maintainer may override any tier via a repository variable — see below —
  so the resolved model can differ.)

- **Reactions tell you what happened:**
  - 👀 (`eyes`) — the command was accepted and is running.
  - 😕 (`confused`) plus a short reply comment — a `^shortcut` was unknown; the
    reply lists the available shortcuts. The run does not start (a typo is not a
    failure); fix the token and comment again.

### Currently defined commands

| Command   | What it does                                                     |
| --------- | --------------------------------------------------------------- |
| `/review` | Focused code review of the pull request (correctness > style).  |

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

That caller file is the entire per-command surface area; everything else —
parsing, the model map, the 👀/😕 acknowledgement, the opencode invocation —
lives in [`opencode-cmd-engine.yml`](../.github/workflows/opencode-cmd-engine.yml).

### Where the model map lives

The shortcut → model mapping is the `MODEL_MAP` env block in the engine's
`parse` job. One `shortcut: full-model-spec` per line; a `default` entry is
mandatory. Values may reference repository/organization variables with `||`
fallbacks:

```yaml
MODEL_MAP: |
  default: ${{ vars.OPENCODE_MODEL_DEFAULT || 'opencode-go/glm-5.2' }}
  large:   ${{ vars.OPENCODE_MODEL_LARGE || 'cscs-inference/zai-org/GLM-5.2' }}
  fast:    ${{ vars.OPENCODE_MODEL_FAST || 'opencode-go/kimi-k2.6' }}
```

Set the `OPENCODE_MODEL_DEFAULT` / `_LARGE` / `_FAST` **repository variables**
(Settings → Secrets and variables → Actions → Variables) to override a tier
without editing the workflow. Each model's **provider** must be declared in
[`opencode.json`](../opencode.json) and its API key present as a secret and
threaded through the engine's opencode step: `opencode-go/*` → `OPENCODE_API_KEY`,
`swiss-ai/*` → `SWISSAI_API_KEY`, `cscs-inference/*` → `CSCS_INFERENCE_API_KEY`.
Those secrets are the same ones `opencode.yml` already uses.

### Naming constraints

- A command name must not contain the substring `oc` after the slash: the stock
  `opencode.yml` prefilter is `contains(body, '/oc')` and would co-trigger.
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

The opencode action's behavior when handed an explicit `prompt:` on an
`issue_comment` event — in particular whether it still enforces commenter
permissions — has not been smoke-tested here (see below). If it does **not**,
gate each caller's job with an author-association check:

```yaml
if: >-
  contains(github.event.comment.body, '/review') &&
  contains(fromJSON('["OWNER","MEMBER","COLLABORATOR"]'), github.event.comment.author_association)
```

## Known assumptions / follow-ups

These need a real repo with the opencode app installed and cannot be verified
from the workflow files alone:

- That passing `prompt:` to the opencode action on an `issue_comment` event
  fully overrides its default comment-driven behavior.
- Whether the opencode action still enforces commenter permissions when given
  an explicit prompt (see the gate above).
