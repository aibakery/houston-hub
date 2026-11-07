# Connect WooCommerce

Requires a store at its domain root over HTTPS and an administrator or shop manager.

1. Open **WooCommerce → Settings → Advanced → REST API → Add key**.
2. Select the user the key acts as and choose **Read**, or **Read/Write** for changes.
3. Generate the key and copy both **Consumer key** and **Consumer secret**.
4. In Houston, enter **Store domain** without `https://` or a path, paste both
   credentials and choose the matching **Access** level. Save the connection.

[Official authentication guide](https://developer.woocommerce.com/docs/apis/rest-api/authentication/).

> Writes can issue refunds and email customers. Store settings, payment methods
> and webhooks also require write access because they can expose secrets.

## Advanced

The API must answer at `/wp-json/wc/v3`; choose a permalink structure other than
**Plain**. Subdirectories and redirects are unsupported, so use the final HTTPS
host. The key owner's WordPress role still applies.

For authentication failures, check that the user and key exist, the host forwards
the Authorization header, and WordPress recognizes HTTPS behind any proxy.
Firewalls and security plugins may need to allow Houston's server egress addresses
and `Houston (+https://ok-houston.com)` User-Agent. Ask your Houston operator for
those addresses. On o2switch, check Tiger Protect's default rule and ModSecurity.
