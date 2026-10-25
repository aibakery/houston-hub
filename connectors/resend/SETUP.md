# Connect your Resend account

You need a Resend account on [resend.com](https://resend.com). No developer app
is required. To send email to anyone other than yourself, your team also needs a
domain verified on the [Domains](https://resend.com/domains) page.

1. Sign in to Resend and open [API Keys](https://resend.com/api-keys).
2. Click **Create API Key**. Enter a **Name**, for example `Houston`, and set
   **Permission** to **Full access**. Click **Add**.
3. Copy the key now; Resend shows it only once. Keys start with `re_`.
4. In your Houston organization, add the Resend connector and paste the key into
   **API key**. Keep **Access** set to **Read-only** unless agents should send
   email or change things.
5. Save the connection and grant the appropriate organization members access.

You can then ask which emails bounced this week, what a customer replied, or how
many people opened your last broadcast. Never paste the key into a chat or saved
action.

See Resend's [API key guide](https://resend.com/docs/dashboard/api-keys/introduction).

## Advanced

### Sending and making changes

Choose **Read and write** in Houston. Houston removes every sending and editing
action from read-only connections. Sent email, broadcasts and automations reach
real people and count toward your plan's quota. A webhook's signing secret and
the full request and response of a logged API call are also available only on
read and write connections, because they can contain credentials.

A **Full access** key reaches everything in your Resend team. Grant write access
only to people who may send email on your behalf.

### Sending-only keys

A key with **Sending access**, optionally restricted to one **Domain**, can only
send email. With it, every reading action fails, so use it only on a **Read and
write** connection meant for sending.

### What stays in Resend

Create, edit and delete API keys, and manage OAuth apps, in Resend itself.
Houston does not expose those settings.

### Troubleshooting

- **Requests fail with HTTP 400 "API key is invalid", or HTTP 401.** The key was
  deleted or mistyped. Create a new key and update the connection.
- **Requests fail with HTTP 401 `restricted_api_key`.** The key has **Sending
  access**. Create a **Full access** key to read data.
- **Requests fail with HTTP 403 "API key is not active" or `suspended_api_key`.**
  The key is no longer active, or Resend suspended it. Create a new key and update
  the connection, or contact Resend support about a suspension.
- **Sending fails with HTTP 403.** The sender's domain isn't verified in Resend,
  or you're sending from `onboarding@resend.dev` to someone other than yourself.
- **Creating an inbox fails with HTTP 422 or 403.** Its domain needs receiving
  enabled on the [Domains](https://resend.com/domains) page, or the inbox needs
  forwarding turned on. HTTP 403 means your plan's inbox limit is reached.
- **Requests fail with HTTP 429.** Resend allows 10 requests per second per team,
  and the free plan allows 100 emails a day and 3,000 a month, counting received
  email and each recipient. Wait, or check your usage in Resend's
  [settings](https://resend.com/settings/usage).
- **You need to stop access.** Delete the key in Resend, or remove the
  connection in Houston.
