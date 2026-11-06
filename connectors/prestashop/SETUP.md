# Connect PrestaShop

Requires PrestaShop 1.7, 8 or 9 over HTTPS at the domain root, and a back-office
account allowed to manage **Advanced Parameters**.

> Use a separate **View (GET)**-only key for read-only connections. PrestaShop can
> turn read requests into changes; a write-enabled key can change data regardless
> of Houston's Access setting.

1. Under **Advanced Parameters → Webservice**, enable the webservice.
2. Select **Add new webservice key**, generate a key and keep it enabled.
3. Grant **View (GET)** for the resources agents need:
   `addresses`, `carriers`, `cart_rules`, `carts`, `categories`, `combinations`,
   `countries`, `currencies`, `customers`, `languages`, `manufacturers`,
   `order_carriers`, `order_details`, `order_histories`, `order_invoices`,
   `order_payments`, `order_slip`, `order_states`, `orders`, `products`,
   `stock_availables`, `suppliers`. Leave write columns off and save.
4. In Houston, enter **Store domain** without `https://` or a path, paste
   **Webservice key**, choose **Read-only** and save.

[Official webservice guide](https://devdocs.prestashop-project.org/9/webservice/tutorials/creating-access/).

## Advanced

### Changes and multiple stores

For a separate **Read and write** connection, allow **Add (POST)** for customers,
order histories and products; **Patch (PATCH)** for customers, order carriers,
products and stock (version 8+); and **Delete (DELETE)** for customers/products
only if permanent deletion is intended. Status and tracking changes can email customers.
Use **Store association** to limit stores the key may access.

### Connection problems

Use the final HTTPS domain; subdirectories and redirects are unsupported. The API
must answer at `/api`. Save the key to regenerate Apache's `.htaccess`, or configure
the `/api` rewrite on nginx. If PHP receives no key, enable **CGI mode for PHP** and
save the key again, or ask your host to forward the Authorization header.
