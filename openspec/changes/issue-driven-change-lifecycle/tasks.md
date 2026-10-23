# Tasks

## 1. Decision record

- [x] 1.1 Write `dev/adr/0012-issue-driven-change-lifecycle.md` recording the lifecycle decision

## 2. Documentation

- [x] 2.1 Add the "Issue triage and change lifecycle" section to `dev/conventions.md` (renamed from `dev/style.md`)
- [x] 2.2 Add the issue-lifecycle paragraph to the `openspec/config.yaml` context block
- [x] 2.3 Add the "Filing issues" section to `docs/README.md`
- [x] 2.4 Add bug and feature issue templates under `.github/ISSUE_TEMPLATE/`

## 3. Repository wiring

- [x] 3.1 Add the CHANGELOG bullet under `[Unreleased]`
- [ ] 3.2 Create the `triage/accepted`, `triage/declined`, and `blocked/deferred` labels on GitHub
- [ ] 3.3 Run `openspec validate --all --strict` and `pixi run verify` and confirm both are green
