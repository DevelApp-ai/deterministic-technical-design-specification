{{/*
helm/templates/_helpers.tpl
Shared template helpers for the dtds-docs chart.
*/}}

{{- define "dtds-docs.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "dtds-docs.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "dtds-docs.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels — includes the four FinOps cost-allocation labels required by
OPA policy FINOPS-001 and K8S-001.
*/}}
{{- define "dtds-docs.labels" -}}
helm.sh/chart: {{ include "dtds-docs.chart" . }}
app.kubernetes.io/name: {{ include "dtds-docs.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
environment: {{ .Values.labels.environment }}
app_name: {{ .Values.labels.app_name }}
owner: {{ .Values.labels.owner }}
cost_center: {{ .Values.labels.cost_center }}
{{- end }}

{{- define "dtds-docs.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dtds-docs.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
