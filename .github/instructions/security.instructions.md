---
applyTo: "**"
excludeAgent: "coding-agent"
---

# Security review rules

Loaded for every changed file (`applyTo: "**"`) in code review — and any
other Copilot surface that reads `.github/instructions/`.
`excludeAgent: "coding-agent"` is the one exception: it keeps these rules
out of the Copilot coding agent so they shape reviews without steering code
generation.

## Untrusted data & deserialization

- Treat external input (CLI args, request data, file contents, env vars) as
  untrusted: validate type, range, and length before use.
- Flag `pickle.load`, `torch.load`, `np.load(allow_pickle=True)`,
  `joblib.load`, or `yaml.load` without `SafeLoader` on data that isn't
  fully trusted — loading a model checkpoint or cached array can execute
  arbitrary code.
- Flag SQL / HTML / shell / template strings assembled from input without
  parameterization or escaping (injection).

## Subprocess & filesystem

- Flag `subprocess` / `os.system` calls built from interpolated input —
  especially with `shell=True` — when launching solvers, jobs, or tools.
- Flag user- or config-controlled paths used for filesystem, scratch, or
  URL access without canonicalization and an allowlist (path traversal,
  SSRF).

## Secrets & config

- Flag hard-coded credentials, API keys, tokens, or private keys —
  including in notebooks and experiment configs.
- Flag secrets read from source instead of the environment or a secret store.
- Flag secrets, tokens, or full payloads written to logs or run artifacts.

## Auth & boundaries (service code)

- For any networked service or API, flag handlers that perform privileged
  work without checking authentication and authorization, missing ownership
  checks (IDOR), disabled TLS verification, and weak or homegrown crypto.

Report severity and the concrete exploit path; don't speculate beyond the diff.
