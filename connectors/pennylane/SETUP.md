# Connect your Pennylane company

You need a Pennylane company on the Essential plan or higher, and the Executive,
Internal Accountant or External Accountant role in it. No developer app is
required.

1. Sign in to [Pennylane](https://app.pennylane.com) and open the company to connect.
2. In the **Management** section, go to **Settings → Connectivity → Developers**
   and select **Generate an API Token**.
3. Enter a **Token Name**, for example `Houston`.
4. Under **API V2**, choose **Read only** or **Read and write** for each kind of
   data agents may use, such as customer invoices, suppliers or transactions.
   Leave out anything they should not see.
5. Choose an expiration date and select **Generate Token**.
6. Copy the token now; Pennylane shows it only once. Then select **Continue**.
7. In your Houston organization, add the Pennylane connector and paste the token
   into **API token**. Keep **Access** set to **Read-only** unless agents should
   create, send or change things.
8. Save the connection and grant the appropriate organization members access.

You can then ask about unpaid invoices, this month's expenses or a supplier's
history. Never paste the token into a chat or saved action.

See Pennylane's guide to [creating a company API token](https://pennylane.readme.io/docs/generating-my-api-token).

## Advanced

### Making changes

Choose **Read and write** in Houston, and give the token **Read and write**
permission for the data agents may change. Houston removes every write action from
read-only connections. Preparing FEC and general ledger exports stays available,
because it only creates a file.

Sending invoices, quotes and mandate requests emails your customers. Finalizing an
invoice numbers it, after which it can no longer be deleted. Webhooks send company
data to the address they are given and need the token's **Webhook subscriptions**
permission. Grant write access only to people who may manage your accounting.

### Several companies

A token belongs to one company. To connect another company, create a token in that
company and add a second connection. Accounting firm tokens are not supported.

### Troubleshooting

- **There is no Developers tab.** Your role cannot manage tokens, or the company is
  on the Starter plan. Ask an Executive or your accountant, or upgrade the plan.
- **Requests fail with HTTP 401.** The token was deleted, expired or mistyped.
  Create a new token and update the connection.
- **Requests fail with HTTP 403.** The token lacks permission for that kind of
  data. A token's permissions cannot be changed, so create a new token with the
  permission and update the connection.
- **Requests fail with HTTP 429.** Pennylane allows 25 requests every 5 seconds per
  token. Wait a few seconds and try again.
- **You need to stop access.** Delete the token under **Settings → Connectivity →
  Developers**, or remove the connection in Houston.
