{{/*
Expand the name of the chart.
*/}}
{{- define "laravel-vue-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "laravel-vue-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "laravel-vue-app.labels" -}}
helm.sh/chart: {{ include "laravel-vue-app.chart" . }}
app.kubernetes.io/name: {{ include "laravel-vue-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels - SIMPLE VERSION (working)
*/}}
{{- define "laravel-vue-app.selectorLabels" -}}
app: {{ .Values.appLabel | default "laravel" }}
{{- end -}}
