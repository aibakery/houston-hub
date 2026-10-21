# Connect Gusto

You need to be the primary admin or a full-access admin of the company in Gusto.

1. Choose **Read-only** or **Read and write** access.
2. Select **Connect with Gusto** and sign in with your Gusto account.
3. If you manage several companies, pick the one to connect, then allow access.

Each connection reaches one company: add another connection for each additional
company. Houston keeps the connection signed in. If requests start failing with an
authorization error, select **Set up again** and sign in.

## Advanced

### Use your own Gusto app

Turn on **Use your own Gusto app** to connect through an app you register with Gusto.
New apps work only in Gusto's demo environment, which has sample companies, until Gusto
approves them for production; Gusto approves only App Integration partners.

1. Sign up at the [Gusto Developer Portal](https://dev.gusto.com) and create or join
   an organization.
2. Open **Applications**, click **Create application**, and add Houston's displayed
   callback URL as a redirect URI.
3. Copy the app's client ID and secret into **Gusto OAuth client ID** and **Gusto
   OAuth client secret** in Houston.
4. In the Developer Portal, create a demo company, then select **Connect with your
   Gusto demo app** and sign in with that demo company's admin.

Once Gusto approves the app for production, enter its production client ID and secret,
select **Set up again** and sign in with **Connect with your Gusto app**. Gusto assigns
the app's permissions (scopes) during its review; ask developer@gusto.com to change them.
See Gusto's [app integration guide](https://docs.gusto.com/app-integrations/docs/introduction).

### Troubleshooting

- **missing_oauth_scopes**: the app lacks the permission that data needs, such as
  compensations for pay rates. The demo environment doesn't enforce scopes;
  production does.
- **missing_permissions**: the request is a Gusto Embedded feature that app
  integrations can't use.
- **Unauthorized**: the sign-in ended or a Gusto admin disconnected the app. Select
  **Set up again** and sign in.
