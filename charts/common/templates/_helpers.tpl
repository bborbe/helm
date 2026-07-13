{{/*
================================================================================
common library — shared named templates.

CONTEXT CONVENTION
------------------
Every public template takes an explicit two-key dict context — NEVER the
ambient `.`:

    {{ include "common.watcher" (dict "root" $ "unit" .Values.watcher) }}
    {{ include "common.agent"   (dict "root" $ "unit" .Values.agent)   }}

  * "root" — the consuming chart's top context `$` (gives .root.Values,
             .root.Chart, .root.Release).
  * "unit" — the per-workload values map (one watcher or one agent).

Label/helper templates take (dict "root" $ "name" <workloadName>).
================================================================================
*/}}

{{/*
common.labels — standard app.kubernetes.io labels + helm.sh/chart, applied to
every object. Usage:
    {{ include "common.labels" (dict "root" $ "name" $name) | nindent 4 }}
*/}}
{{- define "common.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "common.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
app.kubernetes.io/part-of: {{ .root.Chart.Name }}
{{- with .root.Chart.AppVersion }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
{{- end -}}

{{/*
common.selectorLabels — the immutable subset used for selectors + matchLabels.
Usage:
    {{ include "common.selectorLabels" (dict "root" $ "name" $name) | nindent 6 }}
*/}}
{{- define "common.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end -}}

{{/*
common.fullname — workload object name. Names in these unit charts are already
fully qualified in values (e.g. github-dark-factory-watcher), so this just
enforces the 63-char DNS limit. Usage: {{ include "common.fullname" $name }}
*/}}
{{- define "common.fullname" -}}
{{- . | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
common.namespace — target namespace. Required; fails loudly if unset so a
misconfigured install can't silently land in the release namespace.
Usage: {{ include "common.namespace" (dict "root" $) }}
*/}}
{{- define "common.namespace" -}}
{{- required "namespace is required (set .Values.namespace)" .root.Values.namespace -}}
{{- end -}}

{{/*
common.stagePrefix — the cluster-disambiguation prefix for cluster-scoped
objects (PriorityClass). Uses .Values.stage, falling back to .Values.namespace.
This is what keeps a dev release and a prod release on the SAME cluster from
colliding on a single global PriorityClass name.
Usage: {{ include "common.stagePrefix" (dict "root" $) }}
*/}}
{{- define "common.stagePrefix" -}}
{{- $prefix := .root.Values.stage | default .root.Values.namespace -}}
{{- required "stage or namespace is required (set .Values.stage or .Values.namespace) — needed to name the cluster-scoped PriorityClass uniquely" $prefix -}}
{{- end -}}

{{/*
common.image — assemble a fully-pinned image ref from per-cluster registry +
per-unit repo + pinned tag (default = Chart.appVersion). No Keel — tags are
pinned semver, bump + re-apply to roll.
Usage: {{ include "common.image" (dict "root" $ "unit" $unit) }}
*/}}
{{- define "common.image" -}}
{{- $registry := required "image.registry is required (per-cluster; set .Values.image.registry)" .root.Values.image.registry -}}
{{- printf "%s/%s:%s" $registry .unit.image (.unit.tag | default .root.Chart.AppVersion) -}}
{{- end -}}

{{/*
common.kafkaCertVolumeMounts — Kafka mTLS client-cert volumeMounts. The fixed
paths /client-cert/file, /client-key/file, /server-cert/file are what
github.com/bborbe/kafka reads when KAFKA_BROKERS uses the tls:// scheme.
*/}}
{{- define "common.kafkaCertVolumeMounts" -}}
- name: client-cert
  mountPath: /client-cert
- name: client-key
  mountPath: /client-key
- name: server-cert
  mountPath: /server-cert
{{- end -}}

{{/*
common.kafkaCertVolumes — Kafka mTLS client-cert volumes. Arg dict:
`clientSecret` (Strimzi-issued user.crt/user.key) and `caCertSecret`
(cluster ca.crt). Secrets are referenced by name only.
*/}}
{{- define "common.kafkaCertVolumes" -}}
- name: client-cert
  secret:
    defaultMode: 288
    secretName: {{ .clientSecret }}
    items:
      - key: user.crt
        path: file
- name: client-key
  secret:
    defaultMode: 288
    secretName: {{ .clientSecret }}
    items:
      - key: user.key
        path: file
- name: server-cert
  secret:
    defaultMode: 288
    secretName: {{ .caCertSecret }}
    items:
      - key: ca.crt
        path: file
{{- end -}}
