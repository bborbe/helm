# sentry-watcher

Business-unit chart for the **sentry-watcher** unit. Renders through the
[`common`](../common) library chart. **Watcher-only**, and a **non-GitHub**
watcher — it polls the bborbe Sentry org REST API, not the GitHub API.

## What it deploys

| Object | From | Purpose |
|---|---|---|
| StatefulSet + headless Service + PVC | `common.watcher` | `sentry-watcher` — polls the bborbe Sentry org for unresolved issues with 24h activity (cursor in `/data`), emits one `sentry-issue-analyzer` task per `(short-id, date)`. |

Watcher-only: the emitted tasks are worked by the `sentry-issue-analyzer`
agent, so this chart ships **no** `Config` CR and does **not** require the core
`agent` chart's CRD.

### Secret

Unlike the GitHub watchers, sentry-watcher has **no GitHub App and no `PEM_KEY`
secret** (`watcher.githubAuth: false` skips the PEM_KEY `secretKeyRef`). It does
need the **Sentry API token**: the `SENTRY_API_TOKEN` env var is supplied per
cluster via `watcher.secretEnv`, reading the token key out of the existing
`sentry-watcher` Secret (teamvault-rendered out of band — the chart never
creates or embeds the secret).

## Values contract

**Invariant defaults** (shipped in `values.yaml`; identical on every cluster):
`watcher.{name,image,githubAuth,existingSecret}`,
`watcher.env.{CRON_EXPRESSION,CURSOR_PATH,SENTRY_URL,SENTRY_ORG,SENTRY_PROJECTS,TASK_STATUS,TASK_PHASE,TASK_SUFFIX}`.

**Breaking (0.1.x → 0.2.0):** `watcher.env.POLL_INTERVAL` is **removed**, replaced by `CRON_EXPRESSION`. The schedule semantics change from "every 24h since pod start" to a fixed wall-clock cron expression (default `0 0 0 * * ?` = daily 00:00Z). Any overlay setting `POLL_INTERVAL` must switch to `CRON_EXPRESSION` — the old key is silently ignored.

**Per-cluster (must be supplied by the cluster overlay / `--set`):**

| Value | Notes |
|---|---|
| `namespace` | Required; no default. |
| `stage` | `dev` / `prod`; names the cluster-scoped PriorityClass uniquely. |
| `image.registry` / `image.pullSecrets` | Registry host + pull secret(s). |
| `watcher.storage.storageClassName` | Empty => cluster default StorageClass. |
| `watcher.env.{KAFKA_BROKERS,TOPIC_PREFIX,STAGE}` | Kafka + stage wiring. |
| `watcher.env.{TARGET_VAULT,TASK_ASSIGNEE}` | Vault-specific task materialization (sentry emits into the Personal vault — run in ONE stage only to avoid duplicate task files). |
| `watcher.secretEnv.SENTRY_API_TOKEN` | Key in the existing `sentry-watcher` Secret holding the token. |

## Render locally

```bash
helm dependency build
helm lint .
helm template . \
  --set stage=prod --set namespace=prod \
  --set image.registry=docker.quant.benjamin-borbe.de:443
```
