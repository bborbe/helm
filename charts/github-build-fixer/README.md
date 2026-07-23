# github-build-fixer

Business-unit chart for the **github-build-fixer** unit. Renders through the
[`common`](../common) library chart. **Watcher-only** — ships no agent.

## What it deploys

| Object | From | Purpose |
|---|---|---|
| StatefulSet + headless Service + PVC | `common.watcher` | `github-build-watcher` — polls default-branch CI, writes a `/data` cursor, emits one build-fix task per red build. |

The emitted build-fix tasks are consumed elsewhere (dark-factory implementer /
human) — this chart ships **no** `Config` CR and therefore does **not** require
the core `agent` chart's CRD.

### Secrets (never chart-managed)

The watcher references an **existing** Secret **by name**
(`watcher.existingSecret`, default = the workload name) for `PEM_KEY` (GitHub App
private key) via `secretKeyRef`. The chart never creates the Secret and never
embeds secret values in values/release history. Provision it out of band
(TeamVault / sealed-secret / external-secrets) before install.

## Values contract

**Invariant defaults** (shipped in `values.yaml`; identical on every cluster):
`watcher.{name,image,existingSecret}`,
`watcher.env.{TASK_ASSIGNEE,TASK_STATUS,TASK_PHASE,TASK_SUFFIX}`.

**Per-cluster (must be supplied by the cluster overlay / `--set`):**

| Value | Notes |
|---|---|
| `namespace` | Required; no default. |
| `stage` | `dev` / `prod`; names the cluster-scoped PriorityClass uniquely. Falls back to `namespace`. |
| `image.registry` | e.g. `docker.io` or `docker.quant.benjamin-borbe.de:443`. |
| `image.pullSecrets` | Private-registry pull secret(s). |
| `watcher.storage.storageClassName` | Empty => cluster default StorageClass. |
| `watcher.env.{APP_ID,INSTALLATION_ID,REPO_ALLOWLIST,KAFKA_BROKERS,TOPIC_PREFIX,STAGE,SENTRY_PROXY}` | GitHub App + Kafka + Sentry wiring. |

`values.schema.json` rejects unknown keys under `watcher`, requires the
`existingSecret` field, and types the enums — so a mistyped key fails
`helm lint`/`template` instead of being silently ignored.

## Render locally

```bash
helm dependency build
helm lint .
helm template . \
  --set stage=dev --set namespace=dev \
  --set image.registry=docker.quant.benjamin-borbe.de:443
```
