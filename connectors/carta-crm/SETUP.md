# Connect Carta CRM

You need a Carta CRM account. An organization admin generates the API key; no
developer app is required. For testing, Carta can create a sandbox account on
request.

1. Sign in to Carta CRM as an organization admin and open **Settings**.
2. Generate an API key and copy it. The key acts as its user and organization and
   reaches everything that user can see.
3. In your Houston organization, add the Carta CRM connector and paste the key into
   **API key**. Keep **Access** set to **Read-only** unless agents should create,
   change or delete records.
4. Save the connection and grant the appropriate organization members access.

You can then ask which deals moved stage this month, who at a company your team
has met, or which LP prospects are still waiting on documents. Never paste the key
into a chat or saved action.

If you aren't an admin, ask your organization's admin for a key. See Carta's
[CRM API introduction](https://docs.carta.com/crm/guides/overview/introduction/).

## Advanced

### Making changes

Choose **Read and write** in Houston. Read-only connections can still search and
summarize records but can't create, change or delete them. Creating a contact, or a
record with a website, can start Carta's data enrichment.

### What stays in Carta CRM

Manage users, teams, roles and modules, custom fields, pipeline and fundraising
stages, file attachments, email campaigns and report schedules in Carta CRM itself.
Subscription documents and closings are started from Carta too.

### Troubleshooting

- **Requests fail with HTTP 401 "Unauthorized".** The key was revoked or mistyped.
  Generate a new key and update the connection.
- **Requests fail with HTTP 403.** The key's user can't see that record, or the
  organization hasn't enabled that module.
- **Requests fail with HTTP 429.** Wait for the reset time in the error, then retry.
- **You need to stop access.** Revoke the key in Carta CRM, or remove the
  connection in Houston.
