# Connect your PrestaShop store

You need a PrestaShop 1.7, 8 or 9 store served over HTTPS at the root of its
domain, and a back-office account that can manage **Advanced Parameters**, such as
a SuperAdmin. No developer app is required.

> **Read-only depends on your key, not only on Houston.** Houston never sends
> changes on a **Read-only** connection, but PrestaShop lets a request turn a read
> into an edit or a delete, so the key itself is the only guarantee. For a
> **Read-only** connection, create a key with **View (GET)** and nothing else
> ticked. A key with **Add (POST)**, **Modify (PUT)**, **Patch (PATCH)** or
> **Delete (DELETE)** ticked can change or delete store data whatever **Access**
> says, so never reuse a read-write key for a read-only connection.

1. In your PrestaShop back office, open **Advanced Parameters → Webservice**. Under
   **Configuration**, set **Enable PrestaShop's webservice** to **Yes** and select
   **Save**.
2. Select **Add new webservice key**. Select **Generate** to create a 32-character
   **Key**, and enter a **Key description** such as `Houston`. Keep **Enable
   webservice key** on **Yes**.
3. Under **Permissions**, tick the **View (GET)** column for these resources:
   `addresses`, `carriers`, `cart_rules`, `carts`, `categories`, `combinations`,
   `countries`, `currencies`, `customers`, `languages`, `manufacturers`,
   `order_carriers`, `order_details`, `order_histories`, `order_invoices`,
   `order_payments`, `order_slip`, `order_states`, `orders`, `products`,
   `stock_availables` and `suppliers`. Leave every other column and resource
   unticked: this is what keeps the connection read-only. Select **Save**.
4. Copy the key.
5. In Houston, add the PrestaShop connector, shared with your organization or for
   yourself only. Enter your store's
   domain in **Store domain**, such as `shop.example.com`, without `https://` or a
   path. Paste the key into **Webservice key** and keep **Access** set to
   **Read-only**.
6. Save the connection. For a shared connection, grant the appropriate
   organization members access.

You can then ask about today's orders, an order's status and shipment, a
customer's history, or products running low on stock. Never paste the key into a
chat or saved action.

See PrestaShop's [webservice guide](https://devdocs.prestashop-project.org/9/webservice/tutorials/creating-access/).

## Advanced

### Making changes

Choose **Read and write** in Houston, and in the key's **Permissions** also tick:

- **Add (POST)** for `customers`, `order_histories` and `products`;
- **Patch (PATCH)** for `customers`, `order_carriers`, `products` and
  `stock_availables` (PrestaShop 8 and 9 only; 1.7 has no PATCH column, so edits
  are unavailable there);
- **Delete (DELETE)** for `customers` and `products`, only if agents may delete
  them permanently.

Leave the other write columns unticked. Tick write columns only on a key used by
a **Read and write** connection: a key with write permission can change your
store even on a connection set to **Read-only**. Changing an order's status or tracking number can email your
customer when an agent asks for it.

### Multistore

Under **Store association** (**Shop association** on PrestaShop 1.7 and 8.0),
select the stores the key may access. Agents use your default store unless they
name another store or all stores.

### Troubleshooting

- **The store domain was rejected.** Enter only the domain, such as
  `shop.example.com`, without `https://`, a path or a trailing slash.
- **Requests are redirected.** Enter the exact domain your store redirects to, for
  example `www.shop.example.com`. Houston does not follow redirects and connects
  only over HTTPS.
- **Requests fail with "not found" or "not JSON".** The webservice must answer at
  `https://<your domain>/api`. Check that the webservice is enabled, and save
  the key again to regenerate PrestaShop's `.htaccess`, which routes `/api`. On
  nginx, add PrestaShop's `/api` rewrite rule. Stores installed in a
  subdirectory, such as `example.com/shop`, are not supported.
- **Every request fails with "401 Unauthorized" and "received no key".** Your web
  server drops the `Authorization` header before PHP sees it, which happens with
  PHP-FPM or CGI behind Apache. On the **Webservice** page, set **Enable CGI mode
  for PHP** to **Yes**, select **Save**, then open the key and save it again so
  PrestaShop rewrites `.htaccess`. Otherwise ask your host to pass the header
  through (Apache `CGIPassAuth On`).
- **A request fails with HTTP 401 [26] or HTTP 405 [25].** The key lacks
  permission for that resource or method: tick it under **Permissions**.
- **A request fails with HTTP 503 [22].** The webservice is disabled; turn it on in
  step 1.
- **You need to stop access.** Set the key's **Enable webservice key** to **No** or
  delete it in PrestaShop, or remove the connection in Houston.
