# helm

Helm chart monorepo, **one application chart per business unit** on top of a
shared `common` **library chart**.

Requires Helm v3 (see `Makefile` for the pinned version).

```
helm/
├── charts/
│   ├── common/                 # type: library — reusable named templates, renders nothing
│   │   ├── Chart.yaml
│   │   ├── README.md
│   │   └── templates/
│   │       ├── _helpers.tpl     # common.labels / selectorLabels / fullname / namespace / stagePrefix / image
│   │       ├── _watcher.tpl     # common.watcher  → StatefulSet + Service + PVC
│   │       ├── _agent.tpl       # common.agent    → Config CR + PriorityClass + ResourceQuota
│   │       └── _kafkauser.tpl   # common.kafkauser → Strimzi KafkaUser (optional)
│   └── github-dark-factory/     # first business unit (application chart)
│       ├── Chart.yaml           # depends on common (file://../common)
│       ├── Chart.lock           # committed — pins the common dependency
│       ├── values.yaml          # unit-INVARIANT defaults
│       ├── values.schema.json   # rejects unknown keys, types the enums
│       ├── README.md
│       └── templates/
│           ├── watcher.yaml      # include "common.watcher"  (guarded by watcher.enabled)
│           └── agent.yaml        # include "common.agent"    (guarded by agent.enabled)
└── .github/workflows/helm-ci.yml # helm lint + helm template per chart (+ ct lint if present)
```

## Why this shape

- **`common` library chart** holds the workload shapes (watcher StatefulSet,
  agent Config CR + PriorityClass + ResourceQuota) exactly once. Business-unit
  charts stay tiny — a `Chart.yaml`, a `values.yaml` of unit-invariant defaults,
  and two one-line `include` templates.
- **Per-unit application charts** carry only what differs per unit. Per-cluster
  variables (`namespace`, `stage`, `image.registry`, GitHub App ids, Kafka
  brokers, storage class …) come from the cluster's values overlay — never
  baked into the chart.

## Prerequisite for every unit chart

The core **`agent`** chart must be installed first — it owns the
`configs.agent.benjamin-borbe.de` CRD plus the task controller and executor.
Unit charts emit `Config` CRs of that kind but do **not** ship the CRD.

## Conventions baked into `common`

- **No chart-managed secrets.** Watcher `PEM_KEY` and agent `spec.secretName`
  reference an **existing** Secret **by name**. The chart never creates a Secret
  and never writes secret values into release history. Provision out of band.
- **No Keel.** Image tags are pinned semver (default `Chart.appVersion`); bump
  the tag and re-apply to roll.
- **Cluster-scope collision fix.** `PriorityClass` (cluster-scoped) is named
  `<stage>-<agentName>` so dev + prod releases coexist on one cluster; the
  `ResourceQuota` `scopeSelector` matches that name.

## Add a new business unit

1. `cp -r charts/github-dark-factory charts/<unit>` (or copy the two
   `templates/*.yaml`, which are unit-agnostic).
2. Edit `charts/<unit>/Chart.yaml` — set `name`.
3. Rewrite `charts/<unit>/values.yaml` with the unit's invariant defaults
   (watcher/agent `name`, `image`, `existingSecret`, `taskTypes`, env …).
4. Adjust `values.schema.json` if the unit adds/removes keys.
5. `cd charts/<unit> && helm dependency build && helm lint . && helm template . \
   --set stage=dev --set namespace=dev --set image.registry=docker.io`.
6. Commit the generated `Chart.lock` (see below).

## Local validation

```bash
cd charts/github-dark-factory
helm dependency build          # resolves common, writes Chart.lock
helm lint .
helm template . --set stage=dev --set namespace=dev --set image.registry=docker.io
```

`helm lint charts/common` also works (library-chart lint).

## `Chart.lock` is committed

`charts/*/charts/` (the unpacked/tgz dependency copies) is git-ignored, but the
`Chart.lock` files are **committed** so the pinned `common` version is
reproducible. Run `helm dependency build` after changing a `dependencies:` block.

## License

BSD 2-Clause License. See [LICENSE](LICENSE).
## Release webhook e2e
