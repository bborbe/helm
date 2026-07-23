{{/*
================================================================================
common.watcher — one GitHub watcher: StatefulSet + headless Service + PVC.

Renders a single watcher (NOT a list). The consuming chart guards + invokes it:

    {{- if .Values.watcher.enabled }}
    {{ include "common.watcher" (dict "root" $ "unit" .Values.watcher) }}
    {{- end }}

SECRET WIRING — the GitHub App private key (PEM_KEY) is pulled from an EXISTING
Secret referenced BY NAME (unit.existingSecret, default = the workload name),
key PEM_KEY. This chart NEVER creates the Secret and NEVER embeds secret values
in values/release history. Provision the Secret out of band (TeamVault / sealed
secret / external-secrets) before install; the pod stays Pending on a missing
key ref rather than starting without credentials.

No Keel annotations — tags are pinned semver (bump + re-apply to roll).

unit keys:
  name            (required) object + Service + PVC name, StatefulSet serviceName
  image           (required) repo only; registry from .root.Values.image.registry
  tag             (optional) default .root.Chart.AppVersion
  existingSecret  (optional) default = name; holds key PEM_KEY
  githubAuth      (optional) default true; set false for a NON-GitHub watcher
                  (e.g. go-version polls go.dev) — skips the PEM_KEY secretKeyRef
                  entirely so the pod needs no Secret
  logLevel        (optional) default "2"; feeds -v=<n> arg (NOT an env var)
  storage.size            (optional) default 100Mi
  storage.storageClassName(optional) empty => cluster default StorageClass
  env             (optional) plain container env map
  kafkaUser.enabled (optional) mTLS cert mounts (see common.kafkauser)
================================================================================
*/}}
{{- define "common.watcher" -}}
{{- $root := .root -}}
{{- $unit := .unit -}}
{{- $name := $unit.name -}}
{{- $ns := include "common.namespace" (dict "root" $root) -}}
{{- $existingSecret := $unit.existingSecret | default $name -}}
{{/* githubAuth: default true, but `| default true` mis-fires on an explicit
     false (sprig treats false as empty), so read it via hasKey instead. */}}
{{- $githubAuth := true -}}
{{- if hasKey $unit "githubAuth" -}}{{- $githubAuth = $unit.githubAuth -}}{{- end -}}
{{- $storage := $unit.storage | default dict -}}
{{- $ku := $unit.kafkaUser | default dict -}}
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ $name }}
  namespace: {{ $ns }}
  labels:
    app: {{ $name }}
    {{- include "common.labels" (dict "root" $root "name" $name) | nindent 4 }}
  {{- with $root.Values.rolloutNonce }}
  annotations:
    random: {{ . | quote }}
  {{- end }}
spec:
  replicas: 1
  serviceName: {{ $name }}
  updateStrategy:
    type: RollingUpdate
  selector:
    matchLabels:
      app: {{ $name }}
  template:
    metadata:
      annotations:
        prometheus.io/path: /metrics
        prometheus.io/port: "9090"
        prometheus.io/scheme: http
        prometheus.io/scrape: "true"
        {{- with $root.Values.rolloutNonce }}
        random: {{ . | quote }}
        {{- end }}
      labels:
        app: {{ $name }}
        {{- include "common.selectorLabels" (dict "root" $root "name" $name) | nindent 8 }}
    spec:
      securityContext:
        fsGroup: 65534
      {{- with $root.Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
        - name: service
          image: {{ include "common.image" (dict "root" $root "unit" $unit) | quote }}
          imagePullPolicy: {{ $root.Values.image.pullPolicy | default "IfNotPresent" }}
          securityContext:
            runAsNonRoot: true
            runAsUser: 65534
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: [ALL]
            seccompProfile:
              type: RuntimeDefault
          args:
            - -v={{ $unit.logLevel | default "2" }}
          env:
            {{- range $k, $v := $unit.env }}
            - name: {{ $k }}
              value: {{ $v | quote }}
            {{- end }}
            {{- if $githubAuth }}
            # GitHub App private key from an EXISTING secret (by name). The chart
            # never creates this secret — provision it out of band. Skipped when
            # githubAuth=false (non-GitHub watcher, e.g. go-version).
            - name: PEM_KEY
              valueFrom:
                secretKeyRef:
                  name: {{ $existingSecret }}
                  key: PEM_KEY
            {{- end }}
          ports:
            - containerPort: 9090
              name: http
          livenessProbe:
            httpGet:
              path: /healthz
              port: 9090
              scheme: HTTP
            initialDelaySeconds: 10
            timeoutSeconds: 5
            failureThreshold: 5
            successThreshold: 1
          readinessProbe:
            httpGet:
              path: /readiness
              port: 9090
              scheme: HTTP
            initialDelaySeconds: 5
            timeoutSeconds: 5
          resources:
            requests:
              cpu: 20m
              memory: 20Mi
            limits:
              cpu: 200m
              memory: 100Mi
          volumeMounts:
            - name: datadir
              mountPath: /data
            - name: tmp
              mountPath: /tmp
            {{- if $ku.enabled }}
            {{- include "common.kafkaCertVolumeMounts" . | nindent 12 }}
            {{- end }}
      volumes:
        - name: tmp
          emptyDir: {}
        {{- if $ku.enabled }}
        {{- $userName := $ku.userName | default (printf "%s-%s" $ns $name) }}
        {{- include "common.kafkaCertVolumes" (dict "clientSecret" ($ku.clientSecret | default $userName) "caCertSecret" ($ku.caCertSecret | default "my-cluster-cluster-ca-cert")) | nindent 8 }}
        {{- end }}
      {{- with $root.Values.image.pullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
  volumeClaimTemplates:
    - metadata:
        name: datadir
      spec:
        accessModes: [ReadWriteOnce]
        {{- with $storage.storageClassName }}
        # Omitted when empty so the cluster's DEFAULT StorageClass is used;
        # an explicit "" would instead disable dynamic provisioning.
        storageClassName: {{ . }}
        {{- end }}
        resources:
          requests:
            storage: {{ $storage.size | default "100Mi" }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ $name }}
  namespace: {{ $ns }}
  labels:
    app: {{ $name }}
    {{- include "common.labels" (dict "root" $root "name" $name) | nindent 4 }}
  annotations:
    admin/port: '9090'
    admin/path: ''
spec:
  clusterIP: None
  ports:
    - name: http
      port: 9090
      targetPort: 9090
      protocol: TCP
  selector:
    app: {{ $name }}
{{- end -}}
