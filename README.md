# Migrate your Docker Sandbox Kit from v2 to v3

**For anyone shipping a Docker sandbox kit.** If you're on **v2** today, this
repo shows you two things:

1. **What your v2 kit looks like** — so you recognize it.
2. **The one skill that migrates it to v3** — so you don't do it by hand.

The skill does the real work. This repo is the on-ramp.

> **Migration skill:** <https://github.com/docker/sandbox-kit-spec/tree/main/skills/migrate-kit-to-v3>

---

## TL;DR — migrate in 3 steps

```sh
# 1. Install the migration skill once (per machine):
git clone https://github.com/docker/sandbox-kit-spec
ln -sfn "$PWD/sandbox-kit-spec/skills/migrate-kit-to-v3" ~/.claude/skills/migrate-kit-to-v3
ln -sfn "$PWD/sandbox-kit-spec/skills/create-kit-v3"     ~/.claude/skills/create-kit-v3

# 2. In YOUR kit's repo, start Claude Code and ask it to migrate:
cd ~/your-kit-repo        # the repo that holds your v2 spec.yaml
claude
#   → "migrate this v2 kit to v3"

# 3. The skill writes the v3 files, then builds, runs, verifies, and helps you publish.
```

That's it. The rest of this README is for understanding *what* the skill does
and checking its output.

---

## 1. Do you have a v2 kit? (You do.)

A **v2 kit** is a `spec.yaml` (plus an optional `Dockerfile`). The engine reads
the YAML and assembles the sandbox. If your repo has a `spec.yaml`, you're on v2
and the skill can migrate it.

Here's a real one — the mem0 mixin ([`examples/mem0/spec.yaml`](examples/mem0/spec.yaml)):

```yaml
schemaVersion: "1"
kind: mixin
name: mem0
displayName: Mem0 (Docker Model Runner)
description: "Adds the Mem0 memory layer to an agent…"

network:
  allowedDomains: [pypi.org, files.pythonhosted.org, github.com, localhost:12434]

environment:
  variables:
    OPENAI_BASE_URL: "http://host.docker.internal:12434/engines/v1"
    OPENAI_API_KEY: "dmr"

commands:
  install:
    - command: "pip install --break-system-packages 'mem0ai[nlp]==2.0.5'"
      user: "1000"
  initFiles:
    - path: /home/agent/.mem0/config.json
      content: | …

memory: |
  ## Mem0 memory layer
  The `mem0ai` package is installed and pre-wired…
```

If your kit looks like this — `network`, `environment`, `credentials`,
`permissions`, `commands`/`setup`, `memory` — it is a v2 kit and the skill can
migrate it.

---

## 2. What v3 is (and why it's different)

v3 is **not a schema bump — it's a new model.** A v3 kit is an ordinary OCI
image built by a BuildKit frontend, not YAML the engine interprets.

| | v2 (today) | v3 (target) |
|---|---|---|
| A kit *is* | a `spec.yaml` + `files/`, read by the engine | **an OCI image**, built by `docker buildx` |
| Content | `commands.install` / `initFiles` | a **Dockerfile recipe** + `lifecycle@1` hooks |
| Top-level kind | `sandbox` / `mixin` | **`workload`** / `mixin` / `set` (`sandbox` → `workload`) |
| Config | `network`, `environment`, `credentials`, `ports`, `commands`, `memory` | one unified **`capabilities[]`** list |
| Identity | `name:` | the OCI reference + `provides` / `requires` / `conflicts` |

**Why it matters:** the v3 loader is strict and single-version — it rejects
anything where `schemaVersion != "3"`. v3 kits are published under the `docker`
org on Docker Hub; the old `sbx` org is v2. Don't mix them.

### One file becomes three

v2 packed every concern into a single `spec.yaml`. v3 splits them by *what they
are* — declarative needs, static env, and prose:

```text
v2 (before)                         v3 (after)
───────────                         ──────────
sbx-kits-mem0/                      sbx-kits-mem0/
└── spec.yaml                       ├── mem0.yaml         ← descriptor (capabilities[])
    (network + env +                ├── mem0.dockerfile   ← recipe (carries ENV)
     commands + memory)             └── mem0-context.md   ← agent instructions
```

Each v2 section lands in a specific v3 file:

| v2 `spec.yaml` section | → | Where it goes in v3 |
|---|---|---|
| `network.allowedDomains` | → | `mem0.yaml` → `network-policy@1` (split into `install.allow` + `runtime.allow`) |
| `commands.install` | → | `mem0.yaml` → `lifecycle@1` install hooks |
| `commands.initFiles` | → | `mem0.yaml` → `lifecycle@1` files (`onlyIfMissing` → `overwrite:false`) |
| `memory:` | → | `mem0-context.md` (referenced by `agent-context@1`) |
| `environment.variables` | → | `mem0.dockerfile` as `ENV` (a mixin's only way to carry static env) |
| `name:` | → | *dropped* — v3 identity is the OCI image reference |

See the full before/after for mem0 in [`examples/mem0/`](examples/mem0/).

---

## 3. Install the migration skill (once)

The `migrate-kit-to-v3` and `create-kit-v3` skills ship inside the
[`sandbox-kit-spec`](https://github.com/docker/sandbox-kit-spec) repo. You don't
copy them — you symlink them into `~/.claude/skills/` **once per machine**:

```sh
git clone https://github.com/docker/sandbox-kit-spec
SPEC="$PWD/sandbox-kit-spec"
ln -sfn "$SPEC/skills/migrate-kit-to-v3" ~/.claude/skills/migrate-kit-to-v3
ln -sfn "$SPEC/skills/create-kit-v3"     ~/.claude/skills/create-kit-v3
ls -l ~/.claude/skills      # you should see the two "-> …" symlinks
```

- Link **both** — `migrate-kit-to-v3` references `create-kit-v3`.
- Symlinks are pointers: a `git pull` in the spec repo keeps the skills current.
- `~/.claude/skills/` is machine-wide, so every kit repo sees it. Never repeat
  this per kit.
- Restart Claude Code so it picks up the new skills.

---

## 4. Run the migration (per kit)

```sh
cd ~/your-kit-repo     # the repo that holds your v2 spec.yaml
claude
#   → "migrate this v2 kit to v3"
```

The skill runs an 8-step workflow, editing files **in your kit's own repo**:

1. Read the v2 kit end to end (incl. `README`, `testdata/tck.yaml`)
2. Write the v3 descriptor (`<kit>.yaml`), recipe (`<kit>.dockerfile`), and context file
3. Add a `-mixin` variant (workload kits only)
4. Validate the descriptor (fails in seconds on a bad field)
5. Build the kit
6. Run it with `sbx` and exercise the agent
7. Verify with `kit-tck`
8. Publish, and delete the CI that published the v2 pair

**Prerequisite:** the Docker daemon must be running for steps 4–7. The skill
installs/uses three published tools: `docker buildx` (build), `sbx` (run),
`kit-tck` (conformance).

---

## 5. Build → run → verify → publish

The skill does these for you, but here are the commands (using mem0 as the
example) so you can check its work:

```sh
cd your-kit-repo
git rm spec.yaml Dockerfile          # remove the v2 pair once v3 is in place

# Validate the descriptor (fast fail on a bad field — no content build):
docker buildx build . -f mem0.yaml --output type=cacheonly

# Build to a local OCI layout (for kit-tck):
docker buildx build . -f mem0.yaml -t mem0-kit:2.0.5 \
  --output type=oci,dest=/tmp/mem0-layout,tar=false

# Run it composed onto a shell workload (source form — no registry needed):
sbx run docker/sbx-kit-shell:1.0.0 --kit "$PWD" .

# Conformance-check:
kit-tck validate --layout /tmp/mem0-layout 2.0.5

# Publish as one ordinary multi-arch image:
docker buildx build . -f mem0.yaml --platform linux/amd64,linux/arm64 --push \
  -t docker.io/<you>/sbx-kit-mem0:2.0.5 \
  -t docker.io/<you>/sbx-kit-mem0:latest
```

Then commit to the kit's own repo:

```sh
git checkout -b v3-migration
git add -A && git commit -m "Migrate kit to v3"
git push -u origin v3-migration
```

---

## 6. Field mapping (v2 → v3) — cheat sheet

This is what the skill applies. You don't memorize it; it's here so you can
read the output.

```text
schemaVersion: "2"            →  schemaVersion: "3"
name: <x>                     →  (dropped — identity is the OCI reference)
kind: sandbox                 →  kind: workload          # never write "sandbox"
kind: mixin                   →  kind: mixin
sourceURL                     →  sourceUrl               # lowerCamelCase everywhere
requires: {agent: x}          →  requires: ["x"]         # list, not map
sandbox.image: IMG            →  the recipe's `FROM IMG`
sandbox.entrypoint            →  `ENTRYPOINT [...]` in the recipe
sandbox.command.default       →  `CMD [...]` in the recipe
environment.variables         →  `ENV` in the recipe (mixins too — env merges)
network / permissions.network →  capability network-policy@1 (phase-split: install vs runtime)
credentials[]                 →  capability credential@1    (one per service)
volumes[]                     →  capability volume@1        (one per path)
ports[]                       →  capability port@1          (one per port)
commands.install / setup      →  capability lifecycle@1 (install hooks)
commands.initFiles            →  capability lifecycle@1 (files; onlyIfMissing → overwrite:false)
memory / agentInstructions    →  capability agent-context@1 (body moves to <kit>-context.md)
```

Judgment calls the skill makes for you:

- **Adds `version:`, `sourceUrl:`, `licenses:`** even if v2 omitted them — their
  absence only surfaces once published.
- **Phase-splits the network policy**: hosts reached by install hooks →
  `install.allow`; hosts the agent reaches → `runtime.allow`.
- **Credentials default to *required*** in v3 — adds `optional: true` to keep v2
  behavior. Every `inject[].domain` must appear in that phase's allow list.
- **Keeps install hooks as hooks** (not baked layers) when they run `apt`, read
  a create-time value, need the daemon, target a volume, or install into the
  composed base's Python/npm tree.
- **Hook envs are deny-by-default** — every `$VAR` a hook reads (including
  `HTTP_PROXY`/`HTTPS_PROXY` for anything fetching through the proxy) must be in
  its `env: [...]`.

The complete field-by-field rules live in the skill's `FIELD-MAPPING.md`.

---

## 7. Troubleshooting (real issues hit migrating mem0)

Composition/tooling issues, not grammar errors:

**`invalid capability name "deb/containerd.io"` when resolving the workload**
Your `sbx` CLI's validator is older than the published workload. Upgrade
(`brew install docker/tap/sbx`) and make sure an older binary isn't shadowing it
(`which sbx`, `hash -r`).

**`invalid name "."` from `--kit .`**
A bare `.` becomes the kit's name, which isn't a valid path component. Pass a
path whose last component is a real name: `sbx run <workload> --kit "$PWD" .`

**`env conflict on NO_PROXY: <workload> sets … but <kit> sets …`**
Two kits setting the *same* env var to *different* values is a hard failure.
Drop the conflicting env from the mixin — reachability is handled by the runtime
`network-policy` allow entry plus sbx's transparent proxy, not an app-level
`NO_PROXY`.

**`sandbox '…' already exists; --kit can only be used when creating a new sandbox`**
A prior sandbox is still around. Remove and recreate, or reconnect:
```sh
sbx rm -f <sandbox-name>        # then re-run with --kit
sbx run --name <sandbox-name>   # or just hop back in
```

**Reading the real failure.** `sbx run` prints a terse `failed to run sandbox
container`; the real cause is in the daemon log — `sbx daemon status` prints the
path, then tail it.

Lifecycle: `sbx ls` · `sbx stop <name>` · `sbx rm [-f] <name>` · `sbx prune` ·
`sbx reset`. There's no `sbx kit rm` — a published kit is an OCI image, removed
from its registry.

---

## 8. Reference

- **Migration skill:** <https://github.com/docker/sandbox-kit-spec/tree/main/skills/migrate-kit-to-v3>
- **Worked example:** [`examples/mem0/`](examples/mem0/) — real v2 `spec.yaml` → v3 files
- **Slide deck (Marp):** [`slides/v2-to-v3-migration.md`](slides/v2-to-v3-migration.md)
  — render with `npx @marp-team/marp-cli@latest slides/v2-to-v3-migration.md -o deck.pdf`
- **Normative spec:** `docs/spec/SPEC-v3.md` in the spec repo (code wins over docs)
- **Capability schemas:** `docs/spec/capabilities/com.docker.sandbox/*.md`
- **JSON Schema (editor completion):** `schema/kit.schema.json`
