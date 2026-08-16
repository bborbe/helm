# github-update-go-watcher

Layer 2 of the Go-update pipeline: fans a new stable Go release out into one
`github-update-go` task per lagging repo.

```
1. go-version-watcher        detects a new stable Go release
2. github-update-go-watcher  THIS CHART — fans it out to per-repo tasks
3. github-update-go-agent    drains them into PRs
```

Layers 1 and 3 were already autonomous; this unit is the piece that used to be a
human running a slash command.

## What it ships

One StatefulSet (`github-update-go-watcher`) with a small PVC for `cursor.json`,
plus its Service. **No agent Config CR** — that is the deliberate difference from
`github-pr-reviewer`. The consuming agent already exists as Config
`agent-github-update-go` (assignee `github-update-go-agent`), shipped by the core
`agent` chart. A second Config on the same assignee would double-file every task.

## Prerequisite

Install the core `agent` chart first. It owns the
`configs.agent.benjamin-borbe.de` CRD, the task controller, the executor, and the
agent that drains this watcher's output.

## Scope is two gates, both required

1. `watcher.env.REPO_ALLOWLIST` — operator-controlled scope, set per cluster.
2. The repo's own `.maintainer.yaml` sets `goUpdate.autoUpdate: true`.

Absent file, absent section, and absent key all read as **false**. That is a trust
gate, not a default: a repo opts in deliberately and never by accident.

**Consequence worth internalising before the first deploy:** a freshly installed
watcher matches *zero* repos until that flag has been seeded across the fleet. An
empty first run is correct behaviour, not a broken deploy. Seed the flag before
installing to prod, or the install will look like a failure.

## Secret

`watcher.existingSecret` must name an existing Secret carrying `PEM_KEY` and
`SENTRY_DSN`. The chart never creates it. In quant this points at
`github-update-go-agent`, so the watcher and the agent share one GitHub App
credential rather than duplicating a PEM.

## Cursor durability

`CURSOR_PATH` must sit on the PVC (`/data/cursor.json`), not the container
filesystem — otherwise every restart re-files the whole fleet.

Losing the cursor costs one redundant scan, never correctness: a corrupt file is
renamed to `cursor.json.corrupt` and the cycle cold-starts, and every emitted
`task_identifier` is a deterministic UUID5, so downstream dedup absorbs repeats.

## Values

Unit-invariant defaults live in `values.yaml`. Everything marked `# PER-CLUSTER`
is intentionally empty and must come from the cluster overlay — see
`quant/github-update-go-watcher/values-{dev,prod}.yaml`.
