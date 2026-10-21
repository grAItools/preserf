# Tasks

## 1. Reference-doc corrections

- [ ] 1.1 Correct the MODE case-sensitivity sentence to case-insensitive (`dev/references/directives_specification.md:471`)
- [ ] 1.2 Annotate the unmarked upstream-only rows in §6 (`verbose`, `identical`) and the phantom error in §7
- [ ] 1.3 Replace the regex-matching sentence in §3.10 with the exact table-lookup semantics
- [ ] 1.4 Rewrite the editorial "Wait —" block as one declarative sentence (§3.10, lines 608-611)
- [ ] 1.5 Strip "(as of Slice A-1)" from `dev/references/storage_mapping.md:350`
- [ ] 1.6 Annotate the legacy-tree pointer in ADR 0006 (`dev/adr/0006-ppser-differential-dependency.md:13`)

## 2. CHANGELOG

- [ ] 2.1 Consolidate the `[Unreleased]` group headings and re-file the `.gemini` entry (`CHANGELOG.md:100-116`, `:396`, `:776`)

## 3. Verification

- [ ] 3.1 Run `openspec validate --all --strict` and confirm it passes (the delta is the pinning vehicle; the living spec is merged at archive time, not during apply)
- [ ] 3.2 Run `pixi run verify` and confirm it is green
