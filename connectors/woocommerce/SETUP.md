# Connect your WooCommerce store

You need a WooCommerce store served over HTTPS and a WordPress account that can
manage WooCommerce, such as an administrator or shop manager. No developer app is
required.

1. In your WordPress admin, open **WooCommerce → Settings → Advanced → REST API**
   and select **Add key**, or **Create an API key** if the store has none yet.
2. Enter a description such as `Houston`, and select the WordPress user the key acts
   as. Choose **Read** to view store data, or **Read/Write** if agents should also
   make changes. Select **Generate API Key**.
3. Copy both the **Consumer key** and the **Consumer secret** now. WooCommerce shows
   them only once.
4. In your Houston organization, add the WooCommerce connector. Enter your store's
   domain in **Store domain**, such as `shop.example.com`, without `https://` or a
   path. Paste the keys into their private fields. Keep **Access** set to
   **Read-only** unless the key has write permission and agents should make changes.
5. Save the connection and grant the appropriate organization members access.

You can then ask about recent orders, sales for the month, best sellers, low stock
or a customer's order history. Never paste the keys into a chat or saved action.

See WooCommerce's [REST API authentication guide](https://developer.woocommerce.com/docs/apis/rest-api/authentication/).

## Advanced

### Making changes

Choose **Read and write** in Houston and use a key with **Read/Write** permission.
Houston removes write actions from read-only connections, and WooCommerce rejects
writes from a **Read** key. Refunds can return money through your payment gateway,
and order status changes, order emails and customer notes can email your customers.

Store settings, payment methods and webhooks are also available only on read and
write connections, because WooCommerce includes payment credentials and webhook
secrets in them. Grant write access only to people who may see those values.

### Troubleshooting

- **The store domain was rejected.** Enter only the domain, such as
  `shop.example.com`, without `https://`, a path or a trailing slash.
- **Requests are redirected.** Enter the exact domain your store redirects to, for
  example `www.shop.example.com`. Houston does not follow redirects and connects
  only over HTTPS.
- **Requests fail with a JSON or "not found" error.** WooCommerce must be available
  at `https://<your domain>/wp-json/wc/v3`. In **Settings → Permalinks**, choose any
  structure other than **Plain**. Stores installed in a subdirectory, such as
  `example.com/shop`, are not supported.
- **Requests fail with HTTP 401.** Check that the key exists under
  **WooCommerce → Settings → Advanced → REST API** and that its WordPress user still
  exists and can manage WooCommerce. Some hosts strip the `Authorization` header
  before it reaches WordPress; ask your host to pass it through. If a proxy or CDN
  ends HTTPS before your server and WordPress does not detect HTTPS, WooCommerce
  ignores the key and reports "Consumer key is missing"; configure WordPress to
  recognize HTTPS behind the proxy. Security plugins or firewalls can also block API
  requests from servers.
- **You need to stop access.** Revoke the key in WooCommerce, or remove the
  connection in Houston.
