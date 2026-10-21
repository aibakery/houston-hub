# Connect your Dolibarr

You need Dolibarr 16 or later served over HTTPS, and an administrator account to
enable the API and create a user. No developer app is required.

> **Read-only depends on the Dolibarr user, not only on Houston.** Houston never
> sends changes on a **Read-only** connection, but an API key can do whatever its
> Dolibarr user may do. For a **Read-only** connection, create a user with only
> **Read** permissions, as below. Never use an administrator's key: administrators
> bypass most permission checks.

1. In Dolibarr, open **Home → Setup → Modules/Applications**, search for **API**,
   and turn on the **API REST (server)** module.
2. Open **Users & Groups → New user**. Create a user named `houston`, not an
   administrator and not an external user, and select **Create user**.
3. On the user's **Permissions** tab, add the read permissions agents need, such
   as **Read third parties**, **Read contacts**, **Read products**, **Read stocks**
   and **Read stock movements**, **Read customer orders**, **Read invoices**,
   **Read commercial proposals**, **Read shipments**, the supplier and bank
   **Read** permissions, and **Read tags/categories**. Leave every create, modify
   and delete permission off: this keeps the connection read-only.
4. On the user's card, select **Modify**. Next to **API key** (on the
   **Credentials** tab in recent versions), select the generate icon to create a
   random key, then select **Save**. Copy the key.
5. In Houston, add the Dolibarr connector, shared with your organization or for
   yourself only. Enter the domain of your Dolibarr in **Dolibarr domain**, such as
   `erp.example.com`, without `https://` or a path. If your Dolibarr opens in a
   folder, such as `https://example.com/dolibarr/`, enter `/dolibarr` in
   **Install path**; otherwise leave it empty. Paste the key into **API key** and
   keep **Access** set to **Read-only**.
6. Save the connection. For a shared connection, grant the appropriate
   organization members access.

You can then ask about unpaid invoices, a customer's orders, products running low
on stock or this month's bank transactions. Never paste the key into a chat or saved
action.

See Dolibarr's [REST API guide](https://wiki.dolibarr.org/index.php/Module_Web_Services_API_REST_(developer)).

## Advanced

### Making changes

Choose **Read and write** in Houston, and on the user's **Permissions** tab also
add the create and modify permissions for what agents may change: third parties,
contacts, products, stock movements (which need **Create/modify warehouses**),
customer orders and invoices, and **Issue payments for customer invoices** to
record payments (Dolibarr 24 and later; earlier versions use the invoice create
permission). Agents cannot delete records. Validating an order or invoice gives it
its final number and can send Dolibarr's notifications, as it does in Dolibarr.

Use a separate key for a **Read and write** connection: a key whose user may make
changes can change your Dolibarr even on a connection set to **Read-only**.

### Troubleshooting

- **The domain was rejected.** Enter only the domain, such as `erp.example.com`,
  without `https://`, a path or a trailing slash. Put any folder in **Install
  path**.
- **Requests fail with "not JSON" or "not found".** The API must answer at
  `https://<domain><install path>/api/index.php/status`. Check that the **API REST
  (server)** module is on and that **Install path** matches the address where you
  open Dolibarr, such as `/dolibarr` or `/dolibarr/htdocs`. Installs in more than
  two folders are not supported.
- **Requests are redirected.** Enter the exact domain your Dolibarr redirects to,
  for example `www.example.com`. Houston does not follow redirects and connects only
  over HTTPS.
- **Requests fail with HTTP 401.** The key is wrong, or its user is disabled.
  Generate the key again and update it in Houston. Before Dolibarr 20, a missing
  permission also answers HTTP 401.
- **A request fails with HTTP 403.** The user lacks the permission for that
  record, which you add on the **Permissions** tab, or the Dolibarr module behind
  it, such as **Stocks** or **Banks & Cash**, is turned off.
- **A request fails with HTTP 501.** Your Dolibarr does not offer that request, or
  an administrator blocked it with the `API_ENDPOINT_RULES` setting.
- **Requests fail with HTTP 503.** The API may be limited to some IP addresses
  in the module's settings; allow Houston's or remove the limit.
- **You use the Multicompany module.** The connection works in the entity of the
  key's user.
- **You need to stop access.** Delete or change the user's **API key**, or disable
  the user, in Dolibarr, or remove the connection in Houston.
