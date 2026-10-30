# Connect RevenueCat

RevenueCat connects with a secret API key (v2) for one project. No developer app
is required. You need the **Admin** role in the project to create secret keys.

Choose the access level in Houston first: **Read-only** to review customers,
subscriptions, products, offerings and metrics, or **Read and write** to also
grant or revoke promotional entitlements and edit offerings and packages. Give
the key the permissions for that level:

| RevenueCat permissions | Read-only | Read and write |
| --- | --- | --- |
| Charts & metrics | Read only | Read only |
| Customer information | Read only | Read & write |
| Project configuration | Read only | Read & write |

Houston blocks every change on read-only connections. On read and write
connections it only grants and revokes promotional entitlements and edits
offerings and packages: it never refunds, cancels or deletes customers or
subscriptions, even when the key would allow it. To narrow the key itself, see
[Narrower permissions](#narrower-permissions).

## Create a secret API key

1. Sign in to the [RevenueCat dashboard](https://app.revenuecat.com) and open
   your project.
2. Open **API keys** in the project's menu and select **+ New secret API key**.
3. Enter a name, for example `Houston`, and choose **V2** as the version.
4. Set the permissions from the table above, and give the key no other access.
5. Select **Generate** and copy the key, which starts with `sk_`.

See RevenueCat's [API key guide](https://www.revenuecat.com/docs/projects/authentication)
and its [API v2 reference](https://www.revenuecat.com/docs/api-v2), which lists the
permission each request needs.

## Add the connection

1. In Houston, add the RevenueCat connector and choose its access level.
2. Paste the key into the private **Secret API key (v2)** field. Never paste the
   key into a chat or saved action.
3. Save the connection and grant the appropriate members access.

To connect several projects, create a key and a connection for each.

## Advanced

### Narrower permissions

If RevenueCat lets you set permissions for each resource, a read and write
connection needs write access only for customers, offerings and packages:

- **Read only**: projects, apps, products, entitlements, subscriptions,
  purchases and overview metrics.
- **Read & write**: customers (to grant and revoke promotional entitlements),
  offerings and packages.

RevenueCat's API reference names these permissions, for example
`customer_information:customers:read_write` or
`project_configuration:offerings:read_write`.

### Troubleshooting

- **Requests fail with HTTP 401 "Invalid API key."**: the key was revoked or
  mistyped, or it is a v1 key or an SDK (public) key. Create a v2 secret key and
  update the connection.
- **Some requests fail with HTTP 403**: the key lacks a permission from the
  table above. Create a key with the missing permission under **API keys** and
  update the connection.
- **Requests fail with HTTP 429**: RevenueCat limits each key every minute: 480
  requests for customer information, 60 for project configuration and 25 for
  charts and metrics. Wait a minute and try again.
- **A customer can't be found**: RevenueCat looks customers up by their app user
  ID, and searches match an exact email address. App user IDs containing `/`,
  `\` or `%` can't be used.
- **You need to stop access**: revoke the key under **API keys**, or remove the
  connection in Houston.
