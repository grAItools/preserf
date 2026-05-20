# Style guide

> One worked example beats a page of prose. Show, don't tell.

## Language

Primary language: **python**. Tooling is configured to enforce
the rules below; this file documents intent, not syntax.

## Conventions

_Fill in: naming, file layout, error handling pattern, logging pattern, async
style, testing patterns. Prefer concrete code examples over rules._

## Anti-patterns (with the fix)

_For every "don't", give the matching "do" right next to it. A wall of "don'ts"
without alternatives makes agents over-cautious and produces worse code._

Example:

> **Don't** catch a bare exception to swallow it.
> **Do** catch the narrowest type that you can recover from, and re-raise
> with `from` so the stack trace stays intact.
