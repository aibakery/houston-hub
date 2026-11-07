# Connect Cal.com

1. Open [Cal.com API keys](https://app.cal.com/settings/developer/api-keys), create
   a key and copy it. Some accounts place API keys under **Settings → Security**.
2. Paste it into Houston's **API key**.
3. Choose **Read-only**, or **Read and write** to allow bookings and changes, then save.

> The key acts as your account, including your teams. Booking changes can email
> guests and update calendars; workflows can send messages automatically.

## Advanced

This connector uses `api.cal.com`; EU and self-hosted instances are unsupported.
Manage connected calendars, video apps and API keys in Cal.com. Replace expired
or revoked keys in Houston. Webhooks require **Read and write** because they
contain signing secrets.

[Cal.com API guide](https://cal.com/docs/api-reference/v2/introduction).
