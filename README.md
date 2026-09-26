# Migrating Docker Sandbox Kits from v2 to v3

A complete, start-to-end guide: what changed, how to wire in the migration
skill once, the per-kit workflow, and a fully worked example (mem0).

---

## 1. What changed — v2 → v3 is a new model, not a schema bump

| | v2 (what you built before) | v3 (new) |
|---|---|---|
| A kit *is* | a `spec.yaml` + a `files/` tree, interpreted by the engine | **an ordinary OCI image**, built by a BuildKit frontend |
| Content | `setup.install` / `files:` in YAML | a **Dockerfile recipe** (`FROM`, `RUN`, `COPY`) |
| Top-level kind | `sandbox` / `mixin` | **`workload`** / `mixin` / `set` (`sandbox` renamed) |
| Sections | `credentials[]`, `permissions.network`, `ports`, `environment`, `volumes`, `setup` | one unified **`capabilities[]`** list |
| Identity | kit `name:` | the OCI reference + **`provides` / `requires` / `conflicts`** |
| Build | none — engine reads YAML | `# syntax=docker/sandbox-kit:3` frontend validates + builds + publishes |

**Key consequence:** the v3 loader is strict and single-version — it rejects
anything where `schemaVersion != "3"`. The `docker` org on Docker Hub publishes
v3; the old `sbx` org is v2. Don't mix them.

---

## 2. One-time setup: wire in the migration skill

The `migrate-kit-to-v3` and `create-kit-v3` skills already ship inside the
`sandbox-kit-spec` repo. You don't author or copy them — you make them
discoverable by symlinking into `~/.claude/skills/` **once per machine**.

```sh
# Clone the spec repo (if you haven't):
git clone https://github.com/docker/sandbox-kit-spec

# Point Claude Code at its skills (adjust the path to your clone):
SPEC=/path/to/sandbox-kit-spec
ln -sfn "$SPEC/skills/migrate-kit-to-v3" ~/.claude/skills/migrate-kit-to-v3
ln -sfn "$SPEC/skills/create-kit-v3"     ~/.claude/skills/create-kit-v3

# Verify:
ls -l ~/.claude/skills     # you should see the two new "-> …" symlinks
```

Notes:
- A skill is a **directory** (`SKILL.md` + `FIELD-MAPPING.md`), and
  `migrate-kit-to-v3` links to `create-kit-v3` — so link both.
- Symlinks are pointers, not copies: a `git pull` in the spec repo keeps the
  skills current. If you move the clone, re-run the two commands.
- `~/.claude/skills/` is machine-wide, so **every** kit repo sees the skills.
  You never repeat this per-kit.
- Restart Claude Code (or start a fresh session) so it scans the new skills.

---

## 3. The per-kit workflow

Setup is done once (§2). Everything below repeats per kit — and the edits land
in **that kit's own repo**.

```sh
cd ~/sbx-kits-mem0     # the kit's repo (firecrawl, dynatrace, …)
claude                 # start Claude Code
# then ask:  migrate this v2 kit to v3
```

The skill runs its 8-step workflow:

1. Read the v2 kit end to end (incl. `README`, `testdata/tck.yaml`)
2. Write the v3 descriptor, recipe, and context file
3. Add a `-mixin` variant (workload kits only)
4. Validate the descriptor (fails in seconds on a bad field)
5. Build the kit
6. Run it with `sbx` and exercise the agent
7. Verify with `kit-tck`
8. Publish, and delete the CI that published the v2 pair

**Prerequisite:** the Docker daemon must be running for steps 4–7.

---

## 4. Field mapping (v2 → v3)

```text
schemaVersion: "2"            →  schemaVersion: "3"
name: <x>                     →  (dropped — identity is the consumption reference)
kind: sandbox                 →  kind: workload      # never write "sandbox"
kind: mixin                   →  kind: mixin
sourceURL                     →  sourceUrl           # lowerCamelCase everywhere
requires: {agent: x}          →  requires: ["x"]     # list, not map
sandbox.image: IMG            →  the recipe's `FROM IMG`
sandbox.entrypoint            →  `ENTRYPOINT [...]` in the recipe
sandbox.command.default       →  `CMD [...]` in the recipe
sandbox.command.interactive   →  capability lifecycle@1 `interactive:`
environment.variables         →  `ENV` in the recipe (mixins too — env merges)
permissions.network           →  capability network-policy@1 (or @2 for method/path rules)
credentials[]                 →  capability credential@1  (one per service)
volumes[]                     →  capability volume@1      (one per path)
ports[]                       →  capability port@1        (one per port)
setup.install/startup/files   →  capability lifecycle@1
agentInstructions             →  capability agent-context@1
```

Judgment calls the skill applies:
- **Add `version:`, `sourceUrl:`, `licenses:`** even if v2 omitted them — their
  absence only shows once published.
- **Phase-split the network policy**: hosts reached by install hooks →
  `install.allow` (closed before the agent runs); hosts reached by the agent →
  `runtime.allow`.
- **Credentials** default to *required* in v3 — add `optional: true` to keep v2
  behavior. Every `inject[].domain` must appear in the same phase's allow list.
- **Install hooks** that are pure content *can* become overlay layers, but keep
  them as hooks when they run `apt`, read a create-time value, need the Docker
  daemon, target a volume, or install into the composed base's Python/npm tree
  (a `scratch` overlay lands on an unknown base).
- **Hook envs are deny-by-default**: every `$VAR` a hook (or its children like
  `pip`/`curl`) reads must be listed in `env: [...]` — including
  `HTTP_PROXY`/`HTTPS_PROXY` for anything fetching through the forced proxy.
- **`filename:` on `agent-context@1` is workload-only**; a mixin uses
  `contentFile` alone.

---

## 5. Worked example — mem0 (v1/v2 → v3)

The source kit ([`sbx-kits-mem0`](https://github.com/ajeetraina/sbx-kits-mem0))
is a mixin that installs `mem0ai` and wires it to a **local Docker Model
Runner** — no cloud credentials, no external vector DB. It migrates to three
files in a companion-pair layout.

### 5.1 `mem0.yaml` — the descriptor

```yaml
# syntax=docker/sandbox-kit:3
# yaml-language-server: $schema=https://raw.githubusercontent.com/docker/sandbox-kit-spec/main/schema/kit.schema.json
schemaVersion: "3"
displayName: Mem0 (Docker Model Runner)
description: >-
  Adds the Mem0 memory layer (mem0ai) to an agent, pre-wired to a local Docker
  Model Runner for both the LLM and the embedder — no cloud credentials, no
  external vector database.
sourceUrl: https://github.com/ajeetraina/sbx-kits-mem0
licenses: [Apache-2.0]

kind: mixin

# mem0ai is pinned to 2.0.5 in the install hook, so the mixin offers that
# name@version; version: is the artifact's own version + the provide fallback.
version: "2.0.5"
provides: ["mem0@2.0.5"]

# This mixin's install hooks need python3 + pip beyond the platform floor.
# Declaring an unprovidable name refuses composition EVERYWHERE, so verify first:
#   docker run --rm docker/sbx-kit-shell:1.0.0 dpkg-query -W -f='${Version} ${Status}\n' python3
#   docker run --rm docker/sbx-kit-shell:1.0.0 dpkg-query -W -f='${Version} ${Status}\n' python3-pip
# If both print a tilde-free version, uncomment:
# requires: ["deb/python3", "deb/python3-pip"]

capabilities:
  # network.allowedDomains → network-policy@1, phase-scoped.
  - type: com.docker.sandbox/network-policy@1
    config:
      # install hooks: pip pulls mem0ai from PyPI; spacy fetches its model.
      install:
        allow:
          - pypi.org
          - files.pythonhosted.org
          - raw.githubusercontent.com
          - github.com
          - release-assets.githubusercontent.com
      # the agent talks to the host's Docker Model Runner at steady state.
      runtime:
        allow:
          # v2 listed localhost:12434, but env + config point at
          # host.docker.internal:12434 — localhost is the sandbox itself.
          - host.docker.internal:12434

  # memory: → agent-context@1 (no filename: — that's workload-only).
  - type: com.docker.sandbox/agent-context@1
    config:
      contentFile: ./mem0-context.md

  # commands.install + commands.initFiles → lifecycle@1.
  - type: com.docker.sandbox/lifecycle@1
    config:
      # Kept as create-time hooks: mem0ai installs into the COMPOSED base's
      # Python; a scratch overlay lands on an unknown base where it wouldn't
      # resolve. HTTP(S)_PROXY declared because pip fetches through the forced
      # proxy and v3 hook envs are deny-by-default.
      install:
        - command: "pip install --break-system-packages 'mem0ai[nlp]==2.0.5' click"
          user: "1000"
          env: [HTTP_PROXY, HTTPS_PROXY]
          description: "Install Mem0 with NLP extras plus click (spaCy CLI dep)"
        - command: "PIP_BREAK_SYSTEM_PACKAGES=1 python3 -m spacy download en_core_web_sm"
          user: "1000"
          env: [HTTP_PROXY, HTTPS_PROXY]
          description: "Download spaCy English model"
      # initFiles → files. onlyIfMissing: true → overwrite: false.
      files:
        - path: /home/agent/.mem0/config.json
          mode: "0644"
          overwrite: false
          description: "Mem0 config wired to Docker Model Runner (editable)"
          content: |
            {
              "vector_store": {
                "provider": "qdrant",
                "config": {
                  "collection_name": "mem0",
                  "path": "/home/agent/.mem0/qdrant",
                  "on_disk": true,
                  "embedding_model_dims": 1024
                }
              },
              "llm": {
                "provider": "openai",
                "config": {
                  "model": "ai/gemma3",
                  "openai_base_url": "http://host.docker.internal:12434/engines/v1",
                  "api_key": "dmr"
                }
              },
              "embedder": {
                "provider": "openai",
                "config": {
                  "model": "ai/mxbai-embed-large",
                  "openai_base_url": "http://host.docker.internal:12434/engines/v1",
                  "api_key": "dmr",
                  "embedding_dims": 1024
                }
              }
            }
```

### 5.2 `mem0.dockerfile` — the env-carrying overlay

```dockerfile
# syntax=docker/dockerfile:1
# mem0 installs nothing into the image (the wheel lands in the composed base's
# Python at create time, via the lifecycle hooks). This recipe exists only to
# carry the runtime ENV onto the composed image — a mixin's only mechanism for
# static env. ENV must be on the final stage; FROM scratch keeps the layer pure.
FROM scratch

# NO_PROXY lets the mem0 client reach the host's Docker Model Runner directly
# instead of through the sandbox's forced egress proxy. api_key "dmr" is the
# DMR sentinel, not a real credential — which is why there's no credential@1.
ENV OPENAI_BASE_URL="http://host.docker.internal:12434/engines/v1" \
    OPENAI_API_KEY="dmr" \
    MEM0_TELEMETRY="false" \
    NO_PROXY="localhost,127.0.0.1,host.docker.internal" \
    no_proxy="localhost,127.0.0.1,host.docker.internal"
```

### 5.3 `mem0-context.md` — the agent guidance

```markdown
## Mem0 memory layer

The `mem0ai` package is installed and pre-wired to a local Docker Model
Runner (config at `~/.mem0/config.json`), so `Memory.from_config(...)`
add/search works with no cloud keys or external vector database.
```

---

## 6. Validate → build → run → publish

```sh
cd sbx-kits-mem0        # after copying the 3 files in
git rm spec.yaml Dockerfile

# 4. Fast fail-on-bad-field loop (validates descriptor before building content):
docker buildx build . -f mem0.yaml --output type=cacheonly

# 5. Build to a local OCI layout (for kit-tck), or --load for the local store:
docker buildx build . -f mem0.yaml -t mem0-kit:2.0.5 \
  --output type=oci,dest=/tmp/mem0-layout,tar=false

# 6. Run it composed onto a shell workload (source form — no registry needed):
sbx run docker/sbx-kit-shell:1.0.0 --kit . .
#    inside: cat /usr/share/sandbox/kit/mem0/kit.yaml   # self-describing

# 7. Conformance-check the artifact:
kit-tck validate --layout /tmp/mem0-layout 2.0.5

# 8. Publish as one ordinary image (multi-arch):
docker buildx build . -f mem0.yaml --platform linux/amd64,linux/arm64 --push \
  -t docker.io/ajeetraina/sbx-kit-mem0:2.0.5 \
  -t docker.io/ajeetraina/sbx-kit-mem0:latest
sbx run docker/sbx-kit-shell:1.0.0 --kit docker.io/ajeetraina/sbx-kit-mem0:2.0.5 .
```

Then commit to the kit's own repo:

```sh
git checkout -b v3-migration
git add -A && git commit -m "Migrate mem0 kit to v3"
git push -u origin v3-migration
```

---

## 7. Troubleshooting (real issues hit migrating mem0)

These came up end-to-end taking the mem0 kit from authored to running. Each is
a composition/tooling issue, not a descriptor grammar error.

**`invalid capability name "deb/containerd.io"` when resolving the workload**
Your `sbx` CLI's spec validator is older than the published workload. Current
spec §5.1 allows dotted package names (`containerd.io`). Fix: upgrade `sbx` to
the latest stable (`brew install docker/tap/sbx`), and make sure a newer binary
isn't shadowed by an older one earlier on `PATH` (`which sbx`, `hash -r`).

**`invalid name "."` from `--kit .`**
A bare `.` becomes the kit's name in the composed manifest, which isn't a valid
single path component. Pass a path whose last component is a real name:
`sbx run <workload> --kit "$PWD" .`

**`env conflict on NO_PROXY: <workload> sets … but <kit> sets …`**
Two kits setting the *same* env var to *different* values is a hard composition
failure. The mixin's `mem0.dockerfile` originally set `NO_PROXY`, which the shell
workload already defines. Fix: **drop the conflicting env from the mixin.** DMR
reachability is handled by the runtime `network-policy` allow entry plus sbx's
transparent proxy enforcement — the app-level `NO_PROXY` isn't what gates it.
(Spec guidance: a variable two kits set differently belongs in a `profile.d`
drop, not merged `ENV`.)

**`sandbox '…' already exists; --kit can only be used when creating a new sandbox`**
The sandbox from a prior run is still around. Either remove it and recreate, or
reconnect to it (it already has the kit installed):
```sh
sbx rm -f sbx-kit-shell-sbx-kit-mem0-v3        # then re-run with --kit
sbx run --name sbx-kit-shell-sbx-kit-mem0-v3   # or just hop back in
```

**Reading the real failure.** `sbx run` prints a terse `failed to run sandbox
container`. The specific cause is in the daemon log — find it via
`sbx daemon status` (it prints the log path) and tail that file.

Sandbox lifecycle: `sbx ls` · `sbx stop <name>` · `sbx rm [-f] <name>` ·
`sbx prune` (all stopped) · `sbx reset` (all + state). There is no `sbx kit rm`
— a published kit is an OCI image, removed from its registry.

---

## Slides

A technical deep-dive deck (Marp) is in
[`slides/v2-to-v3-migration.md`](slides/v2-to-v3-migration.md). Render it:

```sh
npx @marp-team/marp-cli@latest slides/v2-to-v3-migration.md -o deck.pdf
```

---

## 8. Reference

- **Normative spec:** `docs/spec/SPEC-v3.md` (code wins over docs)
- **Tour:** `docs/kit-intro.md`
- **Capability config schemas:** `docs/spec/capabilities/com.docker.sandbox/*.md`
- **Worked kits:** `examples/` — `hello`, `shell`, `gh`, `claude`, `claude-mixin`, `team`
- **Skills:** `skills/migrate-kit-to-v3/` and `skills/create-kit-v3/`
- **JSON Schema (editor completion):** `schema/kit.schema.json`
