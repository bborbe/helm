{{/*
================================================================================
common.kafkauser — one Strimzi KafkaUser (mTLS) for a watcher that talks Kafka
over tls://. Off by default in the unit charts. Renders a single KafkaUser.

    {{- if .Values.watcher.kafkaUser.enabled }}
    {{ include "common.kafkauser" (dict "root" $ "unit" .Values.watcher) }}
    {{- end }}

Lives in the Strimzi operator's namespace, labelled with the target Kafka
cluster. Strimzi issues a same-named Secret with user.crt/user.key; an external
syncer places it (+ the cluster CA) into the app namespace where the watcher pod
mounts it (see common.watcher kafkaUser cert volumes).

unit.kafkaUser keys:
  cluster          (optional) default my-cluster
  strimziNamespace (optional) default strimzi
  userName         (optional) default "<namespace>-<watcher name>"
================================================================================
*/}}
{{- define "common.kafkauser" -}}
{{- $root := .root -}}
{{- $unit := .unit -}}
{{- $ku := $unit.kafkaUser | default dict -}}
{{- $ns := include "common.namespace" (dict "root" $root) -}}
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
  name: {{ $ku.userName | default (printf "%s-%s" $ns $unit.name) }}
  namespace: {{ $ku.strimziNamespace | default "strimzi" }}
  labels:
    strimzi.io/cluster: {{ $ku.cluster | default "my-cluster" }}
    {{- include "common.labels" (dict "root" $root "name" $unit.name) | nindent 4 }}
spec:
  authentication:
    type: tls
{{- end -}}
