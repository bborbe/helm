# common (Helm library chart)

`type: library` — renders nothing on its own. Provides reusable named templates
that per-business-unit application charts include. Consumed via a dependency:

```yaml
# charts/<unit>/Chart.yaml
dependencies:
  - name: common
    version: 0.1.0
    repository: "file://../common"
```

## Context convention

Every public template takes an explicit **two-key dict** — never the ambient `.`:

```gotemplate
{{ include "common.watcher" (dict "root" $ "unit" .Values.watcher) }}
{{ include "common.agent"   (dict "root" $ "unit" .Values.agent)   }}
```

- `root` — the consuming chart's top context `$` (exposes `.root.Values`,
  `.root.Chart`, `.root.Release`).
- `unit` — the per-workload values map (one watcher or one agent).

Label/name helpers take `(dict "root" $ "name" <workloadName>)`.

## Templates

| Template | Emits | Notes |
|---|---|---|
| `common.watcher` | StatefulSet + headless Service + PVC (`/data` cursor) | One GitHub watcher. `PEM_KEY` via `secretKeyRef` into an **existing** secret (by name). Never creates the secret. |
| `common.agent` | `Config` CR + cluster-scoped `PriorityClass` + `ResourceQuota` (+ optional PVC) | `spec.secretName` = existing secret by name. PriorityClass named `<stagePrefix>-<name>`; ResourceQuota `scopeSelector` matches it. Config CRD itself is **not** templated (lives in the core `agent` chart). |
| `common.kafkauser` | Strimzi `KafkaUser` (mTLS) | Optional; off by default. |
| `common.labels` / `common.selectorLabels` | label blocks | Standard `app.kubernetes.io/{name,instance,managed-by,version,part-of}` + `helm.sh/chart`. |
| `common.fullname` | workload name | Enforces 63-char DNS limit. |
| `common.namespace` | namespace | Required; fails loudly if unset. |
| `common.stagePrefix` | `stage` \|\| `namespace` | Disambiguates cluster-scoped objects across dev/prod on one cluster. |
| `common.image` | `<registry>/<repo>:<tag>` | Registry per-cluster; tag pinned semver (default `Chart.appVersion`). |

## Design decisions baked in

- **No chart-managed secrets.** Neither `common.watcher` nor `common.agent`
  creates a Secret. Both reference an existing Secret **by name**. This deletes
  the old `secretEnv` path that leaked secret values into release history and
  caused a missing-`PEM_KEY` bug. Provision secrets out of band.
- **No Keel annotations.** Retired in favour of pinned semver tags — bump the
  tag and re-apply to roll.
- **Cluster-scope collision fix.** The `PriorityClass` name includes the stage
  prefix so a dev release and a prod release on the same cluster never clash on
  one global object; the `ResourceQuota` `scopeSelector` tracks the same name.
