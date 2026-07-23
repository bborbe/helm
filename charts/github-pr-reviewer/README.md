# github-pr-reviewer

Business-unit chart for the **github-pr-reviewer** unit. Renders through the
[`common`](../common) library chart.

## What it deploys

| Object | From | Purpose |
|---|---|---|
| StatefulSet + headless Service + PVC | `common.watcher` | `github-pr-watcher` — polls GitHub for open PRs by trusted authors, emits a pr-review task per PR. |
| `Config` CR (`agent.benjamin-borbe.de/v1`) | `common.agent` | Declares the `github-pr-review-agent` (assignee `pr-reviewer-agent`) for the core `agent` framework. |
| `PriorityClass` (cluster-scoped) | `common.agent` | Named `<stage>-github-pr-review-agent`; scheduling priority for the agent's pods. |
| `ResourceQuota` | `common.agent` | Caps concurrent agent pods (`concurrency`), scoped to the PriorityClass. |

### Prerequisite

The core **`agent`** chart must be installed first — it owns the
`configs.agent.benjamin-borbe.de` CRD plus the task controller and executor.
This chart emits a `Config` CR but does **not** ship the CRD; applying it before
the CRD exists fails with `no matches for kind Config`.

### Secrets (never chart-managed)

Both the watcher (`PEM_KEY` via `secretKeyRef`) and the agent
(`Config.spec.secretName`) reference an **existing** Secret **by name**
(`watcher.existingSecret` / `agent.existingSecret`, defaulting to the workload
name). The chart never creates these Secrets and never embeds secret values in
values/release history. Provision them out of band before install.

## Values contract

**Invariant defaults** (shipped in `values.yaml`; identical on every cluster):
`watcher.{name,image,existingSecret}`, `watcher.env.{TRUSTED_AUTHORS,TASK_SUFFIX}`,
`agent.{name,assignee,image,existingSecret,taskTypes,triggerPhases,triggerStatuses,heartbeat,concurrency,priorityValue,resources}`,
`agent.env.{CLAUDE_CONFIG_DIR,ANTHROPIC_BASE_URL,ANTHROPIC_MODEL,REVIEW_MODE}`.

**Per-cluster (must be supplied by the cluster overlay / `--set`):**

| Value | Notes |
|---|---|
| `namespace` | Required; no default. |
| `stage` | `dev` / `prod`; names the cluster-scoped PriorityClass uniquely. |
| `image.registry` / `image.pullSecrets` | Registry host + pull secret(s). |
| `watcher.storage.storageClassName` | Empty => cluster default StorageClass. |
| `watcher.env.{APP_ID,INSTALLATION_ID,REPO_ALLOWLIST,KAFKA_BROKERS,TOPIC_PREFIX,STAGE,SENTRY_PROXY}` | GitHub App + Kafka + Sentry wiring. |
| `agent.env.{APP_ID,INSTALLATION_ID,REPO_ALLOWLIST,BOT_GITHUB_LOGIN,TOPIC_PREFIX}` | GitHub App + bot identity + topic wiring. |

## Render locally

```bash
helm dependency build
helm lint .
helm template . \
  --set stage=dev --set namespace=dev \
  --set image.registry=docker.quant.benjamin-borbe.de:443
```
