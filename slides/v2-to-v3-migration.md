<!--
Render with Marp (the --html flag is REQUIRED - two slides use styled HTML diagrams):
  npx @marp-team/marp-cli@latest slides/v2-to-v3-migration.md --html --allow-local-files -o v2-to-v3-migration.pdf
  npx @marp-team/marp-cli@latest slides/v2-to-v3-migration.md --html --pptx -o deck.pptx
-->
---
marp: true
theme: default
paginate: true
size: 16:9
header: 'Docker Sandbox Kits · v2 → v3'
footer: 'github.com/ajeetraina/migrate-sbx-kits-v2-to-v3'
style: |
  section {
    font-family: 'Helvetica Neue', Arial, system-ui, sans-serif;
    font-size: 19px;
    background: #ffffff;
    color: #1C2B3A;
    padding: 46px 58px 58px;
  }
  h1 { color:#1D63ED; font-size:33px; font-weight:700; margin:0 0 12px; }
  h2 { color:#1D63ED; font-size:25px; font-weight:600; }
  h3 { color:#1C2B3A; font-weight:600; }
  a { color:#1D63ED; text-decoration:none; }
  strong { color:#1D63ED; }
  ul, ol { line-height:1.45; }
  code {
    font-family:'Roboto Mono',Menlo,monospace;
    background:#EEF3FC; color:#0A2647; padding:1px 5px; border-radius:4px; font-size:0.85em;
  }
  pre {
    background:#F4F7FC; border:1px solid #D8E2F0; border-left:4px solid #1D63ED;
    border-radius:8px; padding:10px 14px; font-size:0.58em; line-height:1.32;
  }
  pre code { background:transparent; color:#0A2647; padding:0; }
  table { font-size:0.72em; border-collapse:collapse; width:100%; }
  th { background:#1D63ED; color:#fff; padding:6px 10px; text-align:left; }
  td { padding:6px 10px; border-bottom:1px solid #E1E8F0; }
  blockquote { border-left:4px solid #1D63ED; color:#40566b; padding-left:16px; font-style:italic; }
  header { color:#8595AC; font-size:13px; }
  footer { color:#8595AC; font-size:12px; }
  section::after { color:#1D63ED; font-weight:600; }
  section.lead {
    background:radial-gradient(1200px 620px at 18% -10%, #1D63ED 0%, #0A1B2E 72%);
    color:#ffffff;
  }
  section.lead h1 { color:#ffffff; font-size:50px; }
  section.lead h2 { color:#9DBEFF; }
  section.lead a { color:#9DBEFF; }
  section.lead strong { color:#ffffff; }
  section.lead blockquote { color:#CFE0FF; border-color:#9DBEFF; }
---

<!-- _class: lead -->
<!-- _paginate: false -->
<!-- _header: '' -->

# Migrating Docker Sandbox Kits
## v2 → v3

**Not a schema bump - a new model.**

A worked, end-to-end migration (mem0), the skill that drives it, and the gotchas.

---

## Agenda

1. What a Kit is - and what actually changed
2. The v3 model: OCI image + Dockerfile + frontend
3. Descriptor anatomy - kinds, capabilities, provides, args
4. Authoring forms
5. The v2 → v3 field map
6. **Worked example: mem0** (before / after)
7. The migration skill + one-time setup
8. Validate → build → run → publish
9. Troubleshooting (real issues we hit)
10. Status & takeaways

---

## What is a Kit?

A **Kit** packages a piece of a working environment - a tool, an agent, a
service - so a runtime can *install it, grant it what it needs, and compose it*
with other Kits without knowing it in advance.

- **v2:** a `spec.yaml` + a `files/` tree, interpreted by the engine
- **v3:** **an ordinary OCI image** - declarations in a manifest annotation,
  content in the layers, built by a BuildKit frontend

> Dockerfiles made *software* reproducible. Kits make *authority* reproducible.

---

## The core shift

| | v2 | v3 |
|---|---|---|
| A Kit **is** | `spec.yaml` + `files/` | an **OCI image** |
| Content | `setup.install` / `files:` | a **Dockerfile recipe** |
| Kind | `sandbox` / `mixin` | **`workload`** / `mixin` / `set` |
| Grants | `credentials`, `permissions`, `ports`, `volumes`, `setup`… | one **`capabilities[]`** list |
| Identity | `name:` | the OCI **reference** + `provides` |
| Build | none | `# syntax=docker/sandbox-kit:3` frontend |

⚠️ The v3 loader is **strict + single-version**: rejects anything ≠ `"3"`.
`docker` org on Hub = v3, `sbx` org = v2. **Don't mix.**

---

## v3 = image + recipe + frontend

```yaml
# gh.yaml  (the descriptor - declarations)
# syntax=docker/sandbox-kit:3
schemaVersion: "3"
kind: mixin
provides: ["gh@2.72.0"]
capabilities:
  - type: com.docker.sandbox/network-policy@1
    config: { runtime: { allow: [github.com, api.github.com] } }
```

```dockerfile
# gh.dockerfile  (the content recipe - ordinary Dockerfile)
FROM scratch
COPY --from=build /out /
ENTRYPOINT ["gh"]
```

The frontend (dispatched by the `# syntax=` line) **validates the descriptor,
builds the content, and publishes both as one image.**

---

## Two kinds of Kit

| Kind | Layers are | Per composition |
|---|---|---|
| **`workload`** | a root filesystem (+ entrypoint/env/user in image config) | exactly **one** |
| **`mixin`** | an overlay that lands on a workload | **zero or more** |

Plus `set` - an *authoring-only* kind that merges several Kits into one
publishable image.

A descriptor carries **no name, no image ref, no runtime config**:
identity is the reference; runtime contract lives in the image config.

---

## How a sandbox is composed

<div style="display:flex; gap:12px; justify-content:center; margin:6px 0 4px;">
  <div style="background:#EEF3FC; border:1px solid #C7D7F0; border-radius:8px; padding:8px 14px; font-size:0.8em;"><strong>mixin</strong> · gh</div>
  <div style="background:#EEF3FC; border:1px solid #C7D7F0; border-radius:8px; padding:8px 14px; font-size:0.8em;"><strong>mixin</strong> · mem0</div>
  <div style="background:#EEF3FC; border:1px solid #C7D7F0; border-radius:8px; padding:8px 14px; font-size:0.8em;"><strong>mixin</strong> · firecrawl</div>
  <div style="align-self:center; color:#8595AC; font-size:0.75em;">0 … n overlays</div>
</div>

<div style="text-align:center; color:#1D63ED; font-size:22px; margin:2px 0;">▼&nbsp;&nbsp;&nbsp;▼&nbsp;&nbsp;&nbsp;▼</div>

<div style="text-align:center; margin:0 0 4px;">
  <div style="display:inline-block; background:#1D63ED; color:#fff; border-radius:8px; padding:10px 26px; font-weight:600;">workload · sbx-kit-shell &nbsp;<span style="opacity:.8; font-weight:400;">(exactly 1)</span></div>
</div>

<div style="text-align:center; color:#40566b; font-size:0.72em; margin:2px 0;">resolve as a <strong>closed set</strong> - provides / requires / conflicts</div>
<div style="text-align:center; color:#1D63ED; font-size:22px; margin:2px 0;">▼</div>

<div style="text-align:center;">
  <div style="display:inline-block; background:#0A1B2E; color:#fff; border-radius:10px; padding:12px 34px; font-weight:600; letter-spacing:.3px;">composed sandbox - one OCI image, one root filesystem</div>
</div>

Ordering follows the **dependency graph**, not flag order. One provider per name;
`requires` unmet → resolution fails **closed**.

---

## Descriptor anatomy

```yaml
schemaVersion: "3"          # REQUIRED, exactly "3"
kind: workload              # workload | mixin | set
displayName: Claude Code
version: "1.4.2"            # fallback version for provides
licenses: [Apache-2.0]
provides:  ["claude@2.1"]   # what this Kit offers      ┐ kit-to-kit
requires:  ["node >= 20"]   # must be in the set        │ matching
conflicts: ["podman"]       # must be absent            ┘
capabilities: []            # everything the host must grant
args: {}                    # installer-supplied values
build: | …                  # OR dockerfile: path  OR  kits: []
```

Every key is `lowerCamelCase`. **Strict decode** - an unknown key is an error.

---

## Capabilities: one list for everything

Everything the Kit needs but can't supply itself - typed, versioned, answered
by the host (granted / refused / prompted).

```yaml
capabilities:
  - type: com.docker.sandbox/credential@1   # <ns>/<name>@<schema-version>
    optional: true
    config: { service: github, phase: runtime }
```

Resource grants **and** engine-executed behavior go through the same list:

`network-policy@1/@2` · `credential@1` · `volume@1` · `port@1` ·
`lifecycle@1` · `agent-context@1` · `agent-sessions@1` · `sbx@1` ·
`resources@1` · `privileged@1` · `long-running@1` …

Unknown types ride opaquely - the extension point.

---

## provides / requires / conflicts

Kit-to-kit matching, resolved as a **closed set** (no registry solving):

```yaml
provides:  ["gh@2.72.0"]
requires:  ["claude", "deb/openssl >= 3.5"]
conflicts: ["podman"]
```

- Exactly **one workload** per composition; **one provider per name**
- `requires` unmet → resolution fails **closed**
- Composition ordered by the dependency graph, not flag order
- **Derived provides (§9.6):** publishing a workload reads its dpkg/apk DB →
  `deb/bash`, `deb/git`, `deb/containerd.io`… auto-stated. Mixins can `require` them.

---

## args - two phases

```yaml
args:
  version:
    default: "2.72.0"
    pattern: '^[0-9]+\.[0-9]+\.[0-9]+$'
    buildArg: GH_VERSION      # resolves at BUILD → baked into published descriptor
  timeout:
    env: BROWSER_TIMEOUT       # resolves at CREATE → exported to the container
```

- Referenced as `${{ kit.args.name }}` (not shell `$VAR` - can't collide)
- **Private by default**: reaches the container only via `env:`, the build only via `buildArg:`
- Every reference must be declared; create-phase args expand into the *effective descriptor*

---

## Four authoring forms

1. **Companion pair** - `gh.yaml` + `gh.dockerfile` (matched by stem) ← default
2. **Inline `build:`** - Dockerfile text embedded in the descriptor (single file)
3. **Comment descriptor** - a Dockerfile carrying `# kit:` declarations (file is both)
4. **Kit set** - `kits: [...]` merges other Kits into one

```yaml
kind: set
kits:
  - ref: docker.io/dockerdev/sbx-kit-shell:1.0.0
  - ref: docker.io/dockerdev/sbx-kit-gh:2.72.0
```

All produce the **same** artifact: an ordinary OCI image.

---

## The v2 → v3 field map

```text
schemaVersion: "2"          → "3"
name: <x>                   → dropped (identity = the reference)
kind: sandbox               → kind: workload        # never "sandbox"
sourceURL                   → sourceUrl              # lowerCamelCase
sandbox.image / entrypoint  → FROM / ENTRYPOINT in the recipe
environment.variables       → ENV in the recipe (mixins too)
permissions.network         → capability network-policy@1 / @2
credentials[]               → capability credential@1 (per service)
volumes[] / ports[]         → capability volume@1 / port@1
setup.install/startup/files → capability lifecycle@1
agentInstructions           → capability agent-context@1
```

Add `version:`, `sourceUrl:`, `licenses:` - their absence only shows once published.

---

## Worked example: mem0 - BEFORE (v2)

```yaml
schemaVersion: "1"
kind: mixin
name: mem0
network:
  allowedDomains: [pypi.org, files.pythonhosted.org, github.com, localhost:12434]
environment:
  variables:
    OPENAI_BASE_URL: "http://host.docker.internal:12434/engines/v1"
    NO_PROXY: "localhost,127.0.0.1,host.docker.internal"
commands:
  install:
    - command: "pip install --break-system-packages 'mem0ai[nlp]==2.0.5' click"
  initFiles:
    - { path: /home/agent/.mem0/config.json, onlyIfMissing: true, content: "{…}" }
memory: "## Mem0 memory layer …"
```

A mixin wiring mem0 to a **local Docker Model Runner** - no cloud creds.

---

## Worked example: mem0 - AFTER (descriptor)

```yaml
# syntax=docker/sandbox-kit:3
schemaVersion: "3"
kind: mixin
version: "2.0.5"
provides: ["mem0@2.0.5"]
capabilities:
  - type: com.docker.sandbox/network-policy@1
    config:
      install: { allow: [pypi.org, files.pythonhosted.org, github.com, …] }
      runtime: { allow: [host.docker.internal:12434] }   # localhost → host.docker.internal
  - type: com.docker.sandbox/agent-context@1
    config: { contentFile: ./mem0-context.md }
  - type: com.docker.sandbox/lifecycle@1
    config:
      install:
        - command: "pip install --break-system-packages 'mem0ai[nlp]==2.0.5' click"
          user: "1000"
          env: [HTTP_PROXY, HTTPS_PROXY]          # deny-by-default hook env
      files:
        - { path: /home/agent/.mem0/config.json, overwrite: false, content: "{…}" }
```

---

## Worked example: mem0 - recipe & context

```dockerfile
# mem0.dockerfile - env-carrying overlay
# syntax=docker/dockerfile:1
FROM scratch
ENV OPENAI_BASE_URL="http://host.docker.internal:12434/engines/v1" \
    OPENAI_API_KEY="dmr" \
    MEM0_TELEMETRY="false"
# NO_PROXY dropped - the workload sets it; a differing mixin value = conflict
```

```markdown
<!-- mem0-context.md -->
## Mem0 memory layer
The `mem0ai` package is installed and pre-wired to a local Docker Model
Runner (config at `~/.mem0/config.json`) …
```

**Key calls:** phase-split network · hooks stay hooks (Python lands on composed
base) · no `credential@1` (api_key = sentinel `"dmr"`) · no `filename:` (mixin).

---

## The migration skill

`skills/migrate-kit-to-v3/` - a tool-agnostic agent skill that *is* this playbook.

**One-time setup** (symlink into Claude Code's skills dir - machine-wide):

```sh
SPEC=/path/to/sandbox-kit-spec
ln -sfn "$SPEC/skills/migrate-kit-to-v3" ~/.claude/skills/migrate-kit-to-v3
ln -sfn "$SPEC/skills/create-kit-v3"     ~/.claude/skills/create-kit-v3
```

**Per kit** - no copying, edits land in that kit's repo:

```sh
cd ~/sbx-kits-mem0
claude          # then: "migrate this v2 kit to v3"
```

---

## The authoring lifecycle

<div style="display:flex; align-items:stretch; justify-content:center; gap:0; margin:14px 0 10px;">
  <div style="flex:1; background:#EEF3FC; border:1px solid #C7D7F0; border-left:4px solid #1D63ED; border-radius:8px; padding:12px 10px; text-align:center;">
    <div style="color:#1D63ED; font-weight:700; font-size:1.05em;">VALIDATE</div>
    <div style="font-size:0.72em; color:#40566b; margin-top:4px;">buildx <code>--output type=cacheonly</code><br/>fail-on-bad-field · builds nothing</div>
  </div>
  <div style="align-self:center; color:#1D63ED; font-size:24px; padding:0 8px;">▶</div>
  <div style="flex:1; background:#EEF3FC; border:1px solid #C7D7F0; border-left:4px solid #1D63ED; border-radius:8px; padding:12px 10px; text-align:center;">
    <div style="color:#1D63ED; font-weight:700; font-size:1.05em;">BUILD</div>
    <div style="font-size:0.72em; color:#40566b; margin-top:4px;">frontend runs the recipe<br/>descriptor + content → one image</div>
  </div>
  <div style="align-self:center; color:#1D63ED; font-size:24px; padding:0 8px;">▶</div>
  <div style="flex:1; background:#EEF3FC; border:1px solid #C7D7F0; border-left:4px solid #1D63ED; border-radius:8px; padding:12px 10px; text-align:center;">
    <div style="color:#1D63ED; font-weight:700; font-size:1.05em;">RUN</div>
    <div style="font-size:0.72em; color:#40566b; margin-top:4px;"><code>sbx run</code> composes onto<br/>a workload · install hooks fire</div>
  </div>
  <div style="align-self:center; color:#1D63ED; font-size:24px; padding:0 8px;">▶</div>
  <div style="flex:1; background:#1D63ED; border:1px solid #1D63ED; border-radius:8px; padding:12px 10px; text-align:center;">
    <div style="color:#fff; font-weight:700; font-size:1.05em;">PUBLISH</div>
    <div style="font-size:0.72em; color:#CFE0FF; margin-top:4px;"><code>--push</code> multi-arch<br/>one ordinary OCI image</div>
  </div>
</div>

Same tool (`docker buildx`) drives **validate**, **build**, and **publish** - only the
output target changes. `sbx run` is the one step that needs a workload to compose onto.

---

## Validate → build → run → publish

```sh
# 4. Validate (fast fail-on-bad-field; builds nothing to export)
docker buildx build . -f mem0.yaml --output type=cacheonly

# 6. Run - composed onto a workload (source form, no registry needed)
sbx run docker/sbx-kit-shell:1.0.0 --kit "$PWD" .

# 8. Publish as one ordinary multi-arch image
docker buildx build . -f mem0.yaml --platform linux/amd64,linux/arm64 --push \
  -t docker.io/ajeetraina/sbx-kit-mem0:2.0.5
```

Inside the sandbox every Kit is **self-describing**:
`cat /usr/share/sandbox/kit/mem0/kit.yaml`

---

## Troubleshooting - real issues we hit

| Symptom | Cause → Fix |
|---|---|
| `invalid capability name "deb/containerd.io"` | `sbx` too old → upgrade; fix PATH shadowing |
| `invalid name "."` from `--kit .` | bare dot isn't a valid name → `--kit "$PWD"` |
| `env conflict on NO_PROXY` | two kits set it differently → **drop it from the mixin** |
| `sandbox '…' already exists` | prior run → `sbx rm -f <name>` or `sbx run --name <name>` |
| `failed to run sandbox container` | terse - real cause in daemon log (`sbx daemon status`) |

Lifecycle: `sbx ls · stop · rm [-f] · prune · reset`.
**No `sbx kit rm`** - a published kit is an OCI image (remove from registry).

---

## Status & takeaways

**mem0: migrated, verified end-to-end** ✅
authored → validated → built → composed → install hooks ran → sandbox created

Takeaways:
- v3 is an **image + recipe**, not YAML the engine interprets
- Everything a Kit asks for is **one typed `capabilities` list**
- The **skill** turns a migration into a repeatable, guided workflow
- Most friction is **composition/tooling**, not grammar - see Troubleshooting

**Next:** firecrawl & dynatrace (they add `credential@1` + proxy injection).

---

<!-- _class: lead -->
<!-- _header: '' -->

# Resources

**Guide + example:** `github.com/ajeetraina/migrate-sbx-kits-v2-to-v3`
**Kit:** `github.com/ajeetraina/sbx-kit-mem0-v3`

Spec: `docs/spec/SPEC-v3.md` · Tour: `docs/kit-intro.md`
Capability pages: `docs/spec/capabilities/com.docker.sandbox/`

*Thank you - questions?*
