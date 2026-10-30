# github-vuln-watcher

Detects Go vulnerabilities published against **unchanged** dependencies — a
repo's CI goes red with no code change, and until this watcher nothing in the
fleet catches it (every pipeline trigger fires on change; this is the absence
of one).

```
1. github-vuln-watcher  THIS CHART — clones consenting repos, runs their own
                        vuln gate, emits one github-update-go task per repo
                        with a finding
2. github-update-go-agent drains them into bump/fix PRs
```

## What it ships

One StatefulSet (`github-vuln-watcher`) with a 40Gi PVC that holds the cursor
**and every cache the in-pod gates write** (see *Caches live on the PVC*),
plus its Service. **No agent Config CR** — that is the deliberate difference
from `github-pr-reviewer`. The consuming agent already exists as Config
`agent-github-update-go` (assignee `github-update-go-agent`), shipped by the
core `agent` chart. A second Config on the same assignee would double-file
every task.

## Caches live on the PVC, never on the node

The pod runs `make vulncheck` + `make check` per repo, which means a full Go
toolchain working set: `GOCACHE`, `GOMODCACHE`, golangci-lint, trivy, plus a
full clone of every consenting repo. Measured at 25 GiB on prod 2026-10-30.

Two **independent** paths decide where that lands, and both are pinned to the
PVC (`/data`) here — moving only one leaves the node filling:

| Var | Why it matters |
|---|---|
| `HOME` | The image bakes `ENV HOME=/tmp`. Go and the scanners default their cache dirs under `$HOME`. |
| `TMPDIR` | Never set by the image, and the repo clones do **not** derive from `HOME` — the scanner calls `os.MkdirTemp` with an empty dir, so `os.TempDir()` answers `/tmp` regardless of `HOME`. ~1 GiB of clones per sweep. |

The `tmp` emptyDir stays mounted (some tools hard-code `/tmp`) but carries
`tmpSizeLimit: 2Gi`. An emptyDir is **node-local** — it lives on the node's
root filesystem — so an unbounded one lets a cache leak fill the *node* and
take every workload on it down with `DiskPressure`. The `sizeLimit` makes a
returning leak fail this pod instead.

⚠️ Raising `storage.size` later is not an in-place edit: `local-path` has
`allowVolumeExpansion: false` and a StatefulSet's `volumeClaimTemplates` is
immutable, so it needs the StatefulSet and its PVC recreated (losing
`cursor.json` costs one redundant scan).

## Prerequisite

Install the core `agent` chart first. It owns the
`configs.agent.benjamin-borbe.de` CRD, the task controller, the executor, and
the agent that drains this watcher's output.

## Scope is two gates, both required

1. `REPO_ALLOWLIST` (operator-controlled scope), AND
2. the repo's own `.maintainer.yaml` sets `goUpdate.autoUpdate: true`.

Absent file, absent section, and absent key all read as false. That is a trust
gate, so a freshly deployed watcher matches ZERO repos until the flag has been
seeded — an empty first run is correct behaviour, not a fault.

## Signal

Each cycle, the watcher clones every consenting repo (full clone, never
shallow) and runs the repo's **own** vuln gate — `make vulncheck` + `make
check` — under a hard 20-minute timeout. It classifies the output for
trivy/govulncheck/osv-scanner markers and emits one `github-update-go`
create-task per repo with a finding. No vuln logic is reimplemented; the repo's
gate is the signal.

## Dedup / no task spam

`task_identifier` is a deterministic hash over `(repo, sorted vuln IDs)` — NOT
head_sha, NOT timestamp. Unchanged finding set → same id → the service's cursor
skips re-emission, so an unfixable finding does not produce an identical task
every cycle. A new CVE changes the set → new id → new task. Operator suppresses
no-fix findings via `.trivyignore` / `.osv-scanner.toml` / `VULNCHECK_IGNORE`
(see [[Exclude a No-Fix Vulnerability Across the Fleet]]), after which the gate
stops reporting them.

## Cadence

`POLL_INTERVAL` default `12h` — within the SC2 detection-latency bound (<= 24h).
The gate run is minutes per repo, so a daily cadence beats the Layer-2 10m.

## Env

| Variable | Required | Meaning |
|---|---|---|
| `OWNER` | yes | GitHub owner / org to scan (e.g. `bborbe`) |
| `STAGE` | yes | dev/prod — stamped on every emitted task |
| `KAFKA_BROKERS` | yes | Kafka brokers (SyncProducer) |
| `APP_ID` / `INSTALLATION_ID` / `PEM_KEY` | yes* | GitHub App creds (from existing Secret `github-update-go-agent`, key `PEM_KEY`) |
| `REPO_ALLOWLIST` | no | gate 1 — host-qualified repo allowlist; empty = allow-all within OWNER |
| `POLL_INTERVAL` | no | default `12h` (must not exceed 24h) |
| `CURSOR_PATH` | no | default `/data/cursor.json` (PVC-mounted) |
| `HOME` / `TMPDIR` | no | pinned to `/data/home` / `/data/tmp` — **do not override onto `/tmp`** (see *Caches live on the PVC*) |
| `TOPIC_PREFIX` | no | Kafka topic prefix for CQRS topic construction |
| `SENTRY_PROXY` | no | Sentry proxy for error reporting |

## Verify after deploy

1. `kubectlquant -n dev get pods | grep github-vuln-watcher` → Running
2. `curl <admin-url>/metrics` → `github_vuln_watcher_poll_cycle_total{result="success"}` non-zero after one cycle
3. A repo with a known no-fix finding (e.g. `bborbe/mqtt-kafka-connector`) → a second consecutive cycle emits zero new task files
