# Connect Pennylane

Requires the Essential plan or higher and an Executive, Internal Accountant or
External Accountant role.

1. Open your company in [Pennylane](https://app.pennylane.com), then
   **Management → Settings → Connectivity → Developers → Generate an API Token**.
2. Under **API V2**, grant **Read only** for the data agents need, or
   **Read and write** for changes. Choose an expiry and copy the generated token.
3. Paste **API token** into Houston, choose the matching **Access** level and save.

[Official token guide](https://pennylane.readme.io/docs/generating-my-api-token).

> Write access can email customers and finalize invoices, which cannot then be
> deleted. Share the connection only with people allowed to manage your accounting.

## Advanced

Each token belongs to one company; accounting firm tokens are unsupported.
Add a separate connection for each company. Permissions cannot be edited: generate
a new token when access requirements change, and replace expired tokens in Houston.
Webhooks also need **Webhook subscriptions** permission.
