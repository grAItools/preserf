---
description: Create a new feature spec directory under specs/<YYYY-MM>-<slug>/
argument-hint: <kebab-case-slug>
---

You are creating a new feature spec.

1. Compute today's date as `YYYY-MM`. The directory is `specs/<YYYY-MM>-$ARGUMENTS/`.
2. Create the directory if it doesn't exist.
3. Create the following four files, populating placeholders sensibly:

   **spec.md** — WHAT and WHY only. No implementation detail.
   ```markdown
   # <Title>

   ## Problem
   <One paragraph. Who has the problem, when, and what does it cost them?>

   ## Goal
   <One sentence. The observable change after this ships.>

   ## Non-goals
   <Bulleted list of things explicitly out of scope.>

   ## Success criteria
   <Bulleted, testable conditions. Each one becomes at least one test.>
   ```

   **plan.md** — phased plan. Each phase has a name, scope, and the tests that
   prove it works.

   **tasks.md** — checkbox list derived from plan.md. Tick boxes as you go.

   **scratch.md** — empty. This is the agent's working memory; gitignored.

4. **Do not start implementing yet.** Stop here and ask the user to review the
   spec. After they say "looks good", proceed to `/plan`.

If `$ARGUMENTS` is empty, ask the user for a slug before creating anything.
