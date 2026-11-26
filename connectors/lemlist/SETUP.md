# Connect your lemlist team

You need a lemlist account on a plan that includes the API. No developer app is
required.

1. Sign in to [lemlist](https://app.lemlist.com), click your profile picture in
   the bottom left-hand corner and choose **Settings**.
2. Open the **Integrations** tab and click **Generate a new API key**.
3. Copy the key now; lemlist shows it only once.
4. In your Houston organization, add the lemlist connector and paste the key
   into **API key**. Keep **Access** set to **Read** unless agents should
   send messages or change campaigns, leads or contacts.
5. Save the connection and grant the appropriate organization members access.

You can then ask how a campaign performed last week, which leads replied or
what tasks are due today. Never paste the key into a chat or saved action.

See lemlist's [authentication guide](https://developer.lemlist.com/api-reference/getting-started/authentication).

## Advanced

### Making changes

Set **Access** to **Write** in Houston. Houston removes every write action from
connections with read access; searching the people and companies databases and
comparing campaign statistics stay available. Starting a campaign or launching a
lead sends its sequence, inbox messages are sent at once, and email finding,
verification and enrichment spend lemlist credits. Team settings are also
available only with write access, because they include the secrets
that sign lemlist's webhooks.

An API key belongs to one lemlist team and acts for the member who created it.
To connect several teams, create one key per team and add one connection for
each.

### What stays in lemlist

Connect mailboxes or enrichment providers, upload voice messages, download CSV
exports and manage API keys in lemlist itself.

### Troubleshooting

- **Requests fail with HTTP 401.** The key was deleted or mistyped. Generate a
  new key and update the connection.
- **Requests fail with HTTP 402.** Your lemlist plan does not include this part
  of the API.
- **Requests fail with HTTP 429.** lemlist allows about 20 requests every two
  seconds per key. Wait a moment and try again.
- **You need to stop access.** Delete the key in lemlist's **Integrations**
  settings, or remove the connection in Houston.
