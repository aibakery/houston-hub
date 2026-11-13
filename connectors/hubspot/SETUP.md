# Connect HubSpot

1. Choose **Read-only** or **Read and write** and select **Authorize connection**.
2. In HubSpot, choose the account to connect and review the permissions Houston asks
   for. While HubSpot still lists Houston as unverified, select **Connect app**, type
   **I accept the risk**, then select **Connect**. Otherwise select **Connect app**.

> Connecting installs Houston's app in the HubSpot account, which needs a Super Admin
> or a user with the **HubSpot Marketplace access** permission. Switching a connection
> to **Read and write** asks HubSpot for the extra permissions again.

## Advanced

### Service key

Choose **Service key or private app access token** in Houston. A Super Admin or a user
with the **Developer tools access** permission can create a
[service key](https://developers.hubspot.com/docs/apps/developer-platform/build-apps/authentication/account-service-keys)
in HubSpot:

1. Go to **Development**, then **Keys** > **Service keys**, and select **Create service key**.
2. Enter a name, select **Add new scope**, tick the scopes below and select **Update**.
3. Select **Create** and confirm.
4. Open the key, select **Show**, then **Copy**, and paste it in Houston as **Access token**.

Scopes to tick:

- For reading: `crm.objects.contacts.read`, `crm.objects.companies.read`,
  `crm.objects.deals.read`, `crm.objects.tickets.read`, `crm.objects.owners.read`,
  `crm.schemas.contacts.read`, `crm.schemas.companies.read`, `crm.schemas.deals.read`,
  `crm.schemas.tickets.read` and `sales-email-read`.
- For **Read and write**, also: `crm.objects.contacts.write`, `crm.objects.companies.write`,
  `crm.objects.deals.write` and `crm.objects.tickets.write`.

Houston still enforces **Read-only** when the key allows writes.

### Existing private app

HubSpot stopped creating legacy private apps on October 26, 2026, but existing ones
keep working. In HubSpot, go to **Development** > **Legacy apps**, open the app, then on
the **Auth** tab select **Show token** and **Copy**. Paste it in Houston as **Access
token**. An older app may hold the `tickets` scope instead of the `crm.objects.tickets`
scopes; it covers tickets too.

### Missing data or permission errors

- If agents report a missing scope, add it to the service key or private app (select
  **Edit** on the key), or connect again with HubSpot.
- A rotated, expired or deleted key stops working: paste the new key in the connection.
- To revoke Houston's access, uninstall Houston from the account's **Connected Apps**
  in HubSpot, or delete the key, then remove the connection in Houston.
- HubSpot limits how many requests an app or key may make every 10 seconds and every
  day; busy accounts can briefly reach them.
