# sentry-alert-consumer

Stateless Deployment chart for the Kafka-native Sentry alert trigger. Consumes
`{branch}-raw-sentry-alert-input` and emits one `sentry-issue-analyzer`
`CreateTaskCommand` per (issue-key, date), replacing the collector agent's
token-REST fan-out as the pipeline trigger.

## Why standalone (no `common` dependency)

The shared `common` library chart renders watcher **StatefulSets** (with a
datadir PVC) and agent **Config CRs** — not stateless Deployments. This service
has no cursor/PVC (the in-memory offset replays from oldest; controller dedup
makes re-emits no-ops) and no secret (the consumer never calls the Sentry API),
so it ships as a plain Deployment with its own two templates.

## Values

| Key | Default | Description |
|---|---|---|
| `namespace` / `stage` | "" (per-cluster) | target namespace / stage label |
| `image.registry` | "" (per-cluster) | registry host |
| `consumer.kafkaBrokers` | "" (per-cluster) | Kafka bootstrap NodePort list |
| `consumer.env.KAFKA_TOPIC` | "" (per-cluster) | alert topic (`{branch}-raw-sentry-alert-input`) |
| `consumer.env.TOPIC_PREFIX` | "" (per-cluster) | CQRS command-topic prefix (`develop`/`master`) |
| `consumer.env.TARGET_VAULT` | `personal` | vault slug for materialized tasks |
| `consumer.env.TASK_ASSIGNEE` | `sentry-analyzer-agent` | analyzer assignee |
| `consumer.logLevel` | `2` | glog verbosity (LOG_LEVEL env) |

## Rendering

```bash
helm template charts/sentry-alert-consumer \
  --set namespace=dev --set stage=dev --set image.registry=docker.prod.nuke.benjamin-borbe.de:443 \
  --set consumer.kafkaBrokers=192.168.178.41:32159 \
  --set consumer.env.KAFKA_TOPIC=develop-raw-sentry-alert-input \
  --set consumer.env.TOPIC_PREFIX=develop
```
