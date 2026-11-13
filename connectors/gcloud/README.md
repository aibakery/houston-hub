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
anything. Houston has no actions for Secret Manager payloads, IAM policies or
BigQuery.

Houston hides the secret values Google returns in the usual places: environment
variable values, instance metadata, build substitutions, and probe and
uptime-check headers and passwords. Audit log entries show who did what to which
resource, and whether it worked, without the request or response. This hiding
is not exhaustive: command-line arguments, build steps and the logs your
applications write are shown as written, and log searches can still match
hidden values. With **Read and write** access, an
image an agent deploys or a job it runs uses that workload's identity and
secrets, and can print them to logs the agent reads.
