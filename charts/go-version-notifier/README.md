# go-version-notifier

Business-unit chart for the **go-version-notifier** unit. Renders through the
[`common`](../common) library chart. **Watcher-only**, and a **non-GitHub**
watcher — it polls go.dev, not the GitHub API.

## What it deploys

| Object | From | Purpose |
|---|---|---|
| StatefulSet + headless Service + PVC | `common.watcher` | `go-version-watcher` — polls go.dev for new stable Go releases (cursor in `/data`), emits one go-version-update task per release. |

Watcher-only: the emitted tasks are worked by a human (or another agent), so this
chart ships **no** `Config` CR and does **not** require the core `agent` chart's
CRD.

### No secret

Unlike the GitHub watchers, go-version has **no GitHub App and no `PEM_KEY`
secret**. `watcher.githubAuth: false` tells `common.watcher` to skip the PEM_KEY
`secretKeyRef` it injects by default — without it the pod would hang `Pending` on
a missing Secret reference.

## Values contract

**Invariant defaults** (shipped in `values.yaml`; identical on every cluster):
`watcher.{name,image,githubAuth}`,
`watcher.env.{POLL_INTERVAL,CURSOR_PATH,TASK_STATUS,TASK_PHASE,TASK_SUFFIX}`.

**Per-cluster (must be supplied by the cluster overlay / `--set`):**

| Value | Notes |
|---|---|
| `namespace` | Required; no default. |
| `stage` | `dev` / `prod`; names the cluster-scoped PriorityClass uniquely. |
| `image.registry` / `image.pullSecrets` | Registry host + pull secret(s). |
| `watcher.storage.storageClassName` | Empty => cluster default StorageClass. |
| `watcher.env.{KAFKA_BROKERS,TOPIC_PREFIX,STAGE}` | Kafka + stage wiring. |
| `watcher.env.{TARGET_VAULT,TASK_ASSIGNEE,TASK_BODY_TEMPLATE}` | Vault-specific task materialization (go-version is a GLOBAL signal — run in ONE stage only to avoid duplicate task files). |

## Render locally

```bash
helm dependency build
helm lint .
helm template . \
  --set stage=prod --set namespace=prod \
  --set image.registry=docker.quant.benjamin-borbe.de:443
```
