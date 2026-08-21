{{/*
================================================================================
common.agent — one agent: Config CR + PriorityClass + ResourceQuota (+ optional
PVC). Renders a single agent (NOT a list). The consuming chart guards + invokes:

    {{- if .Values.agent.enabled }}
    {{ include "common.agent" (dict "root" $ "unit" .Values.agent) }}
    {{- end }}

PREREQUISITE — the Config CRD (agent.benjamin-borbe.de/v1) is NOT templated
here; it lives in the core `agent` chart. Install that first, or this CR
fail-fasts at apply with "no matches for kind Config".

SECRET WIRING — spec.secretName points at an EXISTING Secret (by name,
unit.existingSecret, default = the workload name). This chart never creates it.

CLUSTER-SCOPE COLLISION FIX — PriorityClass is cluster-scoped, so a dev and a
prod release on ONE cluster would clash on a bare agent name. It is named
"<stagePrefix>-<agentName>" (e.g. dev-github-dark-factory-agent) and the
namespaced ResourceQuota's scopeSelector matches that same name.

No Keel annotations — tags are pinned semver.

unit keys:
  name            (required) object name (Config + ResourceQuota + optional PVC)
  assignee        (required) Config.spec.assignee
  image           (required) repo only; registry from .root.Values.image.registry
  tag             (optional) default .root.Chart.AppVersion
  existingSecret  (optional) default = name; Config.spec.secretName
  taskTypes       (required) list
  heartbeat       (optional) default 5m
  triggerPhases   (required) list -> spec.trigger.phases
  triggerStatuses (required) list -> spec.trigger.statuses
  env             (optional) plain env map -> spec.env
  resources       (optional) -> spec.resources
  priorityValue   (optional) default 500
  concurrency     (optional) default 1 -> ResourceQuota pods
  maxConcurrentJobs (optional) -> Config.spec.maxConcurrentJobs (dispatcher-side
                    gate; when omitted the executor creates a Job per pending task
                    regardless of capacity, so match this to concurrency).
  volumeMountPath (optional) mounts a PVC of storageSize (default 1Gi)
================================================================================
*/}}
{{- define "common.agent" -}}
{{- $root := .root -}}
{{- $unit := .unit -}}
{{- $name := $unit.name -}}
{{- $ns := include "common.namespace" (dict "root" $root) -}}
{{- $existingSecret := $unit.existingSecret | default $name -}}
{{- $pcName := printf "%s-%s" (include "common.stagePrefix" (dict "root" $root)) $name -}}
---
apiVersion: agent.benjamin-borbe.de/v1
kind: Config
metadata:
  name: {{ $name }}
  namespace: {{ $ns }}
  labels:
    {{- include "common.labels" (dict "root" $root "name" $name) | nindent 4 }}
spec:
  assignee: {{ required "agent.assignee is required" $unit.assignee | quote }}
  taskTypes:
    {{- toYaml (required "agent.taskTypes is required" $unit.taskTypes) | nindent 4 }}
  priorityClassName: {{ $pcName }}
  image: {{ include "common.image" (dict "root" $root "unit" $unit) | quote }}
  heartbeat: {{ $unit.heartbeat | default "5m" | quote }}
  secretName: {{ required "agent.existingSecret (or agent.name) is required for spec.secretName" $existingSecret }}
  {{- with $unit.maxConcurrentJobs }}
  maxConcurrentJobs: {{ . }}
  {{- end }}
  {{- with $unit.zombieJobTimeoutSeconds }}
  zombieJobTimeoutSeconds: {{ . }}
  {{- end }}
  {{- with $unit.volumeMountPath }}
  volumeClaim: {{ $name }}
  volumeMountPath: {{ . | quote }}
  {{- end }}
  {{- with $unit.env }}
  env:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  trigger:
    phases:
      {{- toYaml (required "agent.triggerPhases is required" $unit.triggerPhases) | nindent 6 }}
    statuses:
      {{- toYaml (required "agent.triggerStatuses is required" $unit.triggerStatuses) | nindent 6 }}
  {{- with $unit.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- if $unit.volumeMountPath }}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ $name }}
  namespace: {{ $ns }}
  labels:
    {{- include "common.labels" (dict "root" $root "name" $name) | nindent 4 }}
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: {{ $unit.storageSize | default "1Gi" }}
{{- end }}
---
# PriorityClass is cluster-scoped (no namespace). Named "<stagePrefix>-<name>"
# so dev + prod releases on one cluster don't collide, and so the ResourceQuota
# below can cap concurrent pods of exactly this agent.
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: {{ $pcName }}
  labels:
    {{- include "common.labels" (dict "root" $root "name" $name) | nindent 4 }}
value: {{ $unit.priorityValue | default 500 }}
globalDefault: false
preemptionPolicy: Never
description: "Priority class for agent {{ $name }} ({{ $pcName }})"
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: {{ $name }}
  namespace: {{ $ns }}
  labels:
    {{- include "common.labels" (dict "root" $root "name" $name) | nindent 4 }}
spec:
  hard:
    pods: "{{ $unit.concurrency | default 1 }}"
  scopeSelector:
    matchExpressions:
      - scopeName: PriorityClass
        operator: In
        values:
          - {{ $pcName }}
{{- end -}}
