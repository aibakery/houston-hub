# Connect incident.io

1. With **Manage API keys** permission, open
   [Settings → API keys](https://app.incident.io/~/settings/api-keys) and create a key.
2. Grant **View data**, **View catalog** and **View on-call resources**. Add
   **View all incident data** only if agents may see private incidents.
3. For writes, also grant **Create incidents** and **Edit incidents**; optionally
   **Opt out of post-incident flow** if agents may skip it.
4. Paste **API key** into Houston, choose **Read-only** or **Read and write** to
   match the intended access, and save.

[Official API key guide](https://docs.incident.io/admin/api-keys).

## Advanced

A [personal key](https://docs.incident.io/admin/user-api-keys) from **Settings →
Authentication methods → User keys** uses your permissions and stops working when
your account is deactivated. For missing data or forbidden actions, check the key's
permissions and their scope badges; follow-up creation needs `follow_ups.create`.
Your incident type may require fields such as severity or custom fields.
