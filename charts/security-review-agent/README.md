# security-review-agent

Agent Config CR for the security-review-agent. Consumes `security-review` tasks
(created manually via the `security-review-trigger` skill — there is NO watcher
in v1; the watcher is iteration 2 per the parent goal's Non-goals), checks out
the target PR, runs `/coding:pr-review --security`, and writes findings + a
binary verdict into the task's `## Review` section.

## Prerequisite

The core `agent` chart must be installed first — it owns the
`configs.agent.benjamin-borbe.de` CRD plus the task controller and executor.
This chart emits a Config CR of that kind but does NOT ship the CRD.

## Values

- `agent` — the Config CR (name `security-review-agent`, assignee
  `security-reviewer-agent`, taskTypes `[security-review, healthcheck]`).
  Per-cluster env (`APP_ID`, `INSTALLATION_ID`, `REPO_ALLOWLIST`,
  `BOT_GITHUB_LOGIN`, `TOPIC_PREFIX`) comes from the cluster values overlay.

Secret: the chart references an existing Secret (`spec.secretName`) and never
creates it. Provision the PEM out of band (dev `gOplJO`, prod `aqM11q`).
