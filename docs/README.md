# preserf user documentation

This folder holds **user documentation** — material for people who _use_
preserf: building against it, wiring it into CMake or plain make, expanding
`!$SER` sources, and consuming the installed runtime. Content here documents
the product, not the project.

For **development** documentation — the contributor/agent-facing material
(code style, testing strategy, the directive grammar reference, storage
mapping reference, and architecture decision records) — see [`dev/`](../dev/).
The living capability specs that describe the system's behavior are in
[`openspec/specs/`](../openspec/specs/).

The README at the repository root covers the quick-start path; deeper
task-specific guides will land here as the need arises.

## Filing issues

Issues are the entry point for bug reports and feature requests:
describe the *problem* you are hitting, with enough environment detail
(preserf version, platform, compiler, storage backend) to reproduce
it. A maintainer accepts valid issues, and every accepted issue is
linked to a named change proposal in
[`openspec/changes/`](../openspec/changes/) — the change's name
appears in the issue thread. The issue closes automatically when the
implementing change merges.
