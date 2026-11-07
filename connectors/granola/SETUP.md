# Connect Granola

> Requires a Business or Enterprise workspace. Enterprise admins control allowed
> scopes under **Workspace → General → API access for members**.

1. In Granola, open **Settings → Connectors → API keys → Create new key**.
2. Choose **Personal notes** (owned or shared with you) and/or **Public notes**
   (visible to the workspace), then **Generate API Key**.
3. Copy the `grn_` key into Houston's **API key** and save.

[Official API key guide](https://docs.granola.ai/help-center/sharing/integrations/granola-api).

## Advanced

Admins can create a workspace-owned key under **Connectors → Workspace API keys**.
It reads public notes and spaces with **Allow Granola API access** enabled, never
private notes, and keeps working after its creator leaves.

Only notes with a generated summary and transcript appear. Replace expired or
revoked keys in Houston. Audit and legal hold keys are unsupported.
