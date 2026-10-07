# Worked example: mem0 (v2 → v3)

A real mixin kit ([`sbx-kits-mem0`](https://github.com/ajeetraina/sbx-kits-mem0))
migrated from the v2 grammar to the v3 descriptor. Read the two side by side -
this is exactly the shape the migration skill produces.

## Before (v2) - one file

| File | What it is |
|---|---|
| [`spec.yaml`](spec.yaml) | The entire kit: `network`, `environment`, `commands`, `memory`, interpreted by the engine. |

## After (v3) - three files + a recipe

| File | What it is |
|---|---|
| [`mem0.yaml`](mem0.yaml) | The v3 descriptor. `network` → `network-policy@1`, `commands` → `lifecycle@1`, `memory` → `agent-context@1`. |
| [`mem0.dockerfile`](mem0.dockerfile) | A `FROM scratch` overlay that carries the runtime `ENV` (v2 `environment.variables`). |
| [`mem0-context.md`](mem0-context.md) | The agent guidance (v2 `memory:` block, moved out verbatim). |

## The moves that matter here

- **`schemaVersion` → `"3"`**, `kind: mixin` stays, `name:` is **dropped**
  (v3 identity is the OCI reference).
- **`network.allowedDomains` is phase-split.** Hosts the install hooks reach
  (PyPI, GitHub) go in `install.allow`; the host the agent reaches at runtime
  goes in `runtime.allow`. The v2 `localhost:12434` entry was wrong - the agent
  actually reaches `host.docker.internal:12434`, so that is what v3 lists.
- **`NO_PROXY` is dropped** from the env - the shell workload already sets it,
  and a mixin setting the same var to a different value is a hard composition
  conflict.
- **`environment.variables` → `ENV`** in `mem0.dockerfile` (a mixin's only way
  to carry static env), not a descriptor field.
- **`commands.install` stays create-time hooks** (not baked layers) because
  `mem0ai` installs into the *composed base's* Python, and
  **`commands.initFiles` → `lifecycle@1 files`** (`onlyIfMissing` → `overwrite: false`).
- **Hook envs are deny-by-default** in v3 - pip fetches through the forced
  proxy, so each hook must list `env: [HTTP_PROXY, HTTPS_PROXY]`.

Every such decision is marked with an inline `# MIGRATION NOTE:` in the v3
files. The build/run/verify/publish commands for this example are in the
[top-level README](../../README.md#5-build--run--verify--publish).
