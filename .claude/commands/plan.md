---
description: Expand spec.md into a numbered, testable plan.md for the current feature
argument-hint: <spec-dir-name> (optional; defaults to the most recent specs/* directory)
---

You are expanding a feature spec into an implementation plan.

1. Identify the target spec directory.
   - If `$ARGUMENTS` is provided, use `specs/$ARGUMENTS/`.
   - Otherwise, use the most recently modified directory under `specs/`.
2. Read `spec.md` in full. If anything in the **Success criteria** is unclear,
   stop and ask before continuing.
3. Write `plan.md` with the following structure:

   ```markdown
   # Plan

   ## Phase 1 — <name>
   **Scope.** <One paragraph.>
   **Steps.**
   1. <Concrete step>
   2. <Concrete step>
   **Tests.** <Which test(s) prove this phase works.>
   **Exit criteria.** <How we know we can move on.>

   ## Phase 2 — <name>
   ...
   ```

4. Update `tasks.md` to mirror the plan as a checkbox list.
5. **Do not start implementing yet.** Pause for review.
