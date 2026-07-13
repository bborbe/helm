# github-dark-factory

Business-unit chart for the **github-dark-factory** unit. Renders through the
[`common`](../common) library chart.

## What it deploys

| Object | From | Purpose |
|---|---|---|
| StatefulSet + headless Service + PVC | `common.watcher` | GitHub watcher — polls GitHub, writes a `/data` cursor, creates dark-factory tasks. |
| `Config` CR (`agent.benjamin-borbe.de/v1`) | `common.agent` | Declares the `github-dark-factory-agent` implementer for the core `agent` framework. |
| `PriorityClass` (cluster-scoped) | `common.agent` | Named `<stage>-github-dark-factory-agent`; scheduling priority for the agent's pods. |
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
values/release history. Provision them out of band (TeamVault / sealed-secret /
external-secrets) before install.

## Values contract

**Invariant defaults** (shipped in `values.yaml`; identical on every cluster):
`watcher.{name,image,existingSecret}`, `watcher.env.POLL_INTERVAL`,
`agent.{name,assignee,image,existingSecret,taskTypes,triggerPhases,triggerStatuses,heartbeat,concurrency,resources}`,
`agent.env.{CLAUDE_CONFIG_DIR,ANTHROPIC_BASE_URL,ANTHROPIC_MODEL}`.

**Per-cluster (must be supplied by the cluster overlay / `--set`):**

| Value | Notes |
|---|---|
| `namespace` | Required; no default. |
| `stage` | `dev` / `prod`; names the cluster-scoped PriorityClass uniquely. Falls back to `namespace`. |
| `image.registry` | e.g. `docker.io` or `docker.quant.benjamin-borbe.de:443`. |
| `image.pullSecrets` | Private-registry pull secret(s). |
| `watcher.storage.storageClassName` | Empty => cluster default StorageClass. |
| `watcher.env.{APP_ID,INSTALLATION_ID,REPO_ALLOWLIST,KAFKA_BROKERS,TOPIC_PREFIX}` | GitHub App + Kafka wiring. |
| `agent.env.{APP_ID,INSTALLATION_ID,REPO_ALLOWLIST,TOPIC_PREFIX}` | GitHub App + topic wiring. |

`values.schema.json` rejects unknown keys under `watcher`/`agent`, requires the
`existingSecret` fields, and types the trigger enums — so a mistyped key fails
`helm lint`/`template` instead of being silently ignored.

## Render locally

```bash
helm dependency build
helm lint .
helm template . \
  --set stage=dev --set namespace=dev \
  --set image.registry=docker.quant.benjamin-borbe.de:443
```
