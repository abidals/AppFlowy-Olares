{{/* Helpers for the AppFlowy Olares chart */}}

{{- define "appflowy.publicDomain" -}}
{{- $dm := .Values.domain | default dict -}}
{{- $list := split "," (index $dm "appflowy" | default "") -}}
{{- default "" (index $list "_0") -}}
{{- end -}}

{{- define "appflowy.dbUser" -}}
{{- .Values.postgres.username | default "appflowy" -}}
{{- end -}}

{{- define "appflowy.dbName" -}}
{{- .Values.postgres.databases.appflowy | default "appflowy" -}}
{{- end -}}

{{/* Main JWT signing secret: generated once, kept across reinstalls. */}}
{{- define "appflowy.jwtSecret" -}}
{{- $existing := lookup "v1" "Secret" .Release.Namespace "appflowy-config" -}}
{{- if and $existing $existing.data (index $existing.data "GOTRUE_JWT_SECRET") -}}
{{- index $existing.data "GOTRUE_JWT_SECRET" | b64dec -}}
{{- else -}}
{{- randAlphaNum 64 -}}
{{- end -}}
{{- end -}}

{{/* Object-storage access key: generated once, kept across reinstalls. */}}
{{- define "appflowy.s3AccessKey" -}}
{{- $existing := lookup "v1" "Secret" .Release.Namespace "appflowy-config" -}}
{{- if and $existing $existing.data (index $existing.data "APPFLOWY_S3_ACCESS_KEY") -}}
{{- index $existing.data "APPFLOWY_S3_ACCESS_KEY" | b64dec -}}
{{- else -}}
{{- randAlpha 20 -}}
{{- end -}}
{{- end -}}

{{/* Object-storage secret key: generated once, kept across reinstalls. */}}
{{- define "appflowy.s3SecretKey" -}}
{{- $existing := lookup "v1" "Secret" .Release.Namespace "appflowy-config" -}}
{{- if and $existing $existing.data (index $existing.data "APPFLOWY_S3_SECRET_KEY") -}}
{{- index $existing.data "APPFLOWY_S3_SECRET_KEY" | b64dec -}}
{{- else -}}
{{- randAlphaNum 48 -}}
{{- end -}}
{{- end -}}
{{/* Bundled PostgreSQL superuser password: generated once, kept across reinstalls. */}}
{{- define "appflowy.pgPassword" -}}
{{- $existing := lookup "v1" "Secret" .Release.Namespace "appflowy-config" -}}
{{- if and $existing $existing.data (index $existing.data "APPFLOWY_PG_PASSWORD") -}}
{{- index $existing.data "APPFLOWY_PG_PASSWORD" | b64dec -}}
{{- else -}}
{{- randAlphaNum 32 -}}
{{- end -}}
{{- end -}}
