---
description: Investigate deployments, logs, metrics and storage in your Google Cloud projects.
---
# Google Cloud

Let agents answer questions about your Google Cloud projects without handing them
a `gcloud` login or a service-account key.

- See what is deployed on Cloud Run and why a revision or job failed.
- Search Cloud Logging, including Cloud Build logs, and read Cloud Monitoring
  metrics, alerting policies and uptime checks.
- Browse Cloud Storage buckets and download objects.
- List Compute Engine instances, Artifact Registry images, enabled APIs and
  billing accounts.
- With **Read and write** access: deploy a new image or shift traffic on Cloud
  Run, run and cancel jobs, start, stop and reset instances, upload and delete
  objects, and retry or cancel Cloud Build builds.

Agents act with your own Google Cloud permissions, limited further by the access
level you choose. Read-only access is enforced by Google and cannot change
anything. Environment variable values, instance metadata and other secret
settings are hidden from agents at every level, including in audit logs; logs
your own applications write are shown as written. Secret Manager payloads, IAM
policies and BigQuery are not available.
