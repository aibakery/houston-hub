# Connect your Cal.com account

You need a Cal.com account on [cal.com](https://cal.com). No developer app is
required.

1. Sign in to Cal.com and open
   [Settings → Developer → API keys](https://app.cal.com/settings/developer/api-keys).
   Some accounts show API keys under **Settings → Security** instead.
2. Create a new API key named, for example, `Houston`. Choose an expiry date, or
   let it never expire, and save it.
3. Copy the key now; Cal.com shows it only once. Live keys start with `cal_live_`.
4. In your Houston organization, add the Cal.com connector and paste the key into
   **API key**. Keep **Access** set to **Read-only** unless agents should book,
   cancel or change things.
5. Save the connection and grant the appropriate organization members access.

You can then ask about today's meetings, open times next week or a guest's past
bookings. Never paste the key into a chat or saved action.

See Cal.com's [API introduction](https://cal.com/docs/api-reference/v2/introduction).

## Advanced

### Making changes

Choose **Read and write** in Houston. Houston removes every write action from
read-only connections; reading open times and testing a routing form stay
available. Booking, rescheduling, cancelling and adding guests email the people
involved and update connected calendars, and workflows can send messages
automatically. Webhooks are also available only on read and write connections,
because they include the secrets that sign Cal.com's deliveries.

The key acts as you, with access to everything your Cal.com account can reach,
including teams you belong to. Grant write access only to people who may manage
your bookings.

### What stays in Cal.com

Connect calendars and video apps, manage organizations and rotate API keys in
Cal.com itself. Houston does not expose those settings.

### Troubleshooting

- **Requests fail with HTTP 401.** The key was deleted, expired or mistyped.
  Create a new key and update the connection.
- **Requests fail with HTTP 429.** Cal.com limits API keys to about 120 requests
  per minute. Wait a minute, or ask Cal.com support for a higher limit.
- **You use Cal.com's EU region or a self-hosted instance.** This connector
  connects only to `api.cal.com`.
- **You need to stop access.** Delete the key in Cal.com, or remove the
  connection in Houston.
