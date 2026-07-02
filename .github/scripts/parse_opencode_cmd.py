#!/usr/bin/env python3
"""Parse a GitHub comment for /<command> triggers and ^model selectors.

Inputs (environment):
    COMMAND          slash command word, without leading slash
    COMMENT_BODY     full triggering comment body
    PROMPT_TEMPLATE  prompt with a {{request}} placeholder
    MODEL_MAP        lines of "shortcut: full-model-spec"; must contain "default"
    GITHUB_OUTPUT    path to the step-outputs file

Outputs (written to GITHUB_OUTPUT):
    run     "true" | "false"
    ack     "eyes" | "confused" | "none"   (GitHub reaction content)
    error   user-facing error message, empty if none (posted as a reply comment)
    models  JSON array of full model specs (only when run=true)
    prompt  final prompt with {{request}} substituted (only when run=true)
"""

from __future__ import annotations

import json
import os
import re
import sys
import uuid


def emit(out, key: str, value: str) -> None:
    delim = uuid.uuid4().hex  # random heredoc delimiter: content cannot forge outputs
    print(f"{key}<<{delim}\n{value}\n{delim}", file=out)


def parse_model_map(raw: str) -> dict[str, str]:
    entries = (line.split(":", 1) for line in raw.splitlines() if ":" in line)
    return {k.strip(): v.strip() for k, v in entries if k.strip() and v.strip()}


def main() -> int:
    command = os.environ["COMMAND"]
    body = os.environ.get("COMMENT_BODY", "")
    template = os.environ["PROMPT_TEMPLATE"]
    model_map = parse_model_map(os.environ["MODEL_MAP"])

    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
        # Trigger: /<command> as first token of some line (word boundary, not substring)
        cmd_re = re.compile(rf"^\s*/{re.escape(command)}\b", re.MULTILINE)
        if not cmd_re.search(body):
            emit(out, "run", "false")
            emit(out, "ack", "none")
            emit(out, "error", "")
            return 0

        # Model selectors: ^shortcut tokens preceded by start-of-string or whitespace
        sel_re = re.compile(r"(?:^|(?<=\s))\^([\w.-]+)")
        selectors = sel_re.findall(body) or ["default"]
        unknown = [s for s in selectors if s not in model_map]
        if unknown:
            known = ", ".join(f"`^{k}`" for k in sorted(model_map))
            emit(out, "run", "false")
            emit(out, "ack", "confused")
            emit(
                out,
                "error",
                f"Unknown model shortcut(s): {', '.join('`^' + s + '`' for s in unknown)}. "
                f"Available: {known}.",
            )
            return 0

        models = [model_map[s] for s in selectors]
        models = sorted(set(models), key=models.index)  # dedupe, keep order

        cleaned = cmd_re.sub("", sel_re.sub(" ", body))
        cleaned = re.sub(r"[ \t]+", " ", cleaned).strip()

        emit(out, "run", "true")
        emit(out, "ack", "eyes")
        emit(out, "error", "")
        emit(out, "models", json.dumps(models))
        emit(out, "prompt", template.replace("{{request}}", cleaned))
    return 0


if __name__ == "__main__":
    sys.exit(main())
