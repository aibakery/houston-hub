# Connect your Gladia account

1. Choose the access level:
   - **Read-only** to let agents read and download transcriptions without
     creating or deleting anything.
   - **Read and write** to also let agents upload recordings, start
     transcriptions and delete jobs.
2. Create an API key in the [Gladia dashboard](https://app.gladia.io/apikeys) and
   copy it.
3. Add the connection in Houston and paste the key as the **API key**.

Gladia bills transcriptions to the account that owns the key. New accounts get a
one-time €50 credit; when it runs out, top up the wallet or upgrade the plan.

## Advanced: plans, limits and access

### Plans and concurrency

Free accounts run 3 transcriptions at a time, paid accounts 25 (with up to 300
more queued), and Enterprise capacity is agreed with Gladia. A transcription
that hits the limit waits or fails with HTTP 429; the connection reports it as
retryable.

### Retention

Gladia keeps audio and transcripts for the retention window of your plan: one
year on Free, three weeks on paid plans, and custom or zero retention on
Enterprise. After that the audio and result are gone, and only job metadata
remains. Delete a job in time if you need it removed sooner.

### Changing access and revoking

- To change the access level, edit the connection in Houston; the same key keeps
  working.
- To revoke access, delete the key in the
  [Gladia dashboard](https://app.gladia.io/apikeys) and remove the connection in
  Houston.
