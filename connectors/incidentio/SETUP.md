# Connect incident.io

incident.io connects with an API key for your organization. No developer app is
required. Creating a key needs incident.io's **Manage API keys** permission.

Choose the access level in Houston first: **Read-only** to review incidents,
alerts, schedules and the catalog, or **Read and write** to also declare and
update incidents and create follow-ups. Give the key the permissions for that
level:

| incident.io permission | Read-only | Read and write |
| --- | --- | --- |
| **View data** | Yes | Yes |
| **View catalog** | Yes | Yes |
| **View on-call resources** | Yes | Yes |
| **View all incident data** | Optional | Optional |
| **Create incidents** | No | Yes |
| **Edit incidents** | No | Yes |
| **Opt out of post-incident flow** | No | Optional |

**View data** covers public incidents with their updates, timelines and
follow-ups, people, and your severities, statuses, incident types, roles and
custom fields. **View catalog** covers the catalog and teams, and **View on-call
resources** covers alerts and on-call schedules. Add **View all incident data**
only if agents should also see private incidents, and **Opt out of post-incident
flow** only if agents may close incidents without their post-incident flow.
Leave every other permission off. Houston also blocks every change on read-only
connections.

## Create an API key

1. Sign in to incident.io and open
   [Settings → API keys](https://app.incident.io/~/settings/api-keys).
2. Create a new key and give it a name, for example `Houston`.
3. Tick the permissions from the table above.
4. Create the key and copy it. incident.io shows it only once.

See incident.io's [API keys guide](https://docs.incident.io/admin/api-keys).

## Add the connection

1. In your Houston organization, add the incident.io connector and choose its
   access level.
2. Paste the key into the private **API key** field. Never paste the key into a
   chat or saved action.
3. Save the connection and grant the appropriate organization members access.

## Advanced

### Use a personal key instead

A [user API key](https://docs.incident.io/admin/user-api-keys) acts as you, with
exactly your incident.io permissions, and stops working when your account is
deactivated. Create one under **Settings → Authentication methods → User keys**
and paste it under **API key**. The Houston access level still applies, so a
read-only connection cannot make changes even if you can.

### Troubleshooting

- **Requests fail with HTTP 401.** The key was deleted, rotated or mistyped.
  Create a new key and update the connection.
- **Requests fail with HTTP 403.** The key lacks a permission from the table
  above. Edit the key in **Settings → API keys** and add it. In the create and
  edit dialogs, the scopes badge on each permission lists what it allows; for
  example, creating follow-ups needs `follow_ups.create`.
- **Private incidents are missing.** Add **View all incident data** to the key.
- **Declaring an incident fails with HTTP 422.** Your account requires fields
  such as a severity or custom fields for that incident type; the error names
  them.
- **Requests fail with HTTP 429.** incident.io allows 1,200 requests a minute
  per key, 60 incident lists a minute, and 10 declared incidents an hour that
  open a Slack or Microsoft Teams channel. Wait and try again.
- **You need to stop access.** Delete the key in incident.io, or remove the
  connection in Houston.
