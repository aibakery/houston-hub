# Connect Stripe

1. Open your [Stripe Dashboard](https://dashboard.stripe.com/) and select the
   account and sandbox or live environment you want to connect. Start in a sandbox
   when testing changes that can charge customers or move money.
2. Open [API keys](https://dashboard.stripe.com/apikeys). Under **Restricted keys**,
   select **Create restricted key**, start with zero permissions, and enter
   Houston in **Key name**.
   Stripe's [restricted key guide](https://docs.stripe.com/keys/restricted-api-keys)
   covers the current creation flow.
3. Grant **Read** only for the resources you want Houston to read. For writes,
   grant **Write** on the relevant resources. Common permissions include
   Customers, Products, Prices, Payment Intents, Charges, Refunds, Subscriptions,
   Invoices, Payment Methods, Balance, Payouts, Disputes, Events, Checkout Sessions,
   Customer Portal and Files. Labels and available permissions depend on your
   account; use Stripe's resource description when a label differs. Leave unused
   permissions at **None**. Expanding related objects can require their permissions
   too. A standard secret key also works but has broader access.
4. Create and copy the key. In Houston, add a Stripe connection, choose
   **Read-only** or **Read and write**, and enter it under **Stripe API key**.
   Restricted keys start with `rk_test_` or `rk_live_`; secret keys start with
   `sk_test_` or `sk_live_`. A publishable `pk_` key cannot be used here.
5. Save the connection and read its help. Start with a small customer list or
   balance lookup for which your key has permission. Houston keeps the key private.

## Advanced

A 401 normally means a revoked, expired or incorrect key. A 403 means the key
lacks a required permission or the account cannot use the operation. A 404 can
mean the object belongs to another account or environment. Check the key's mode
and account before changing permissions.

If the key has an IP restriction, it must allow your Houston deployment's egress
IP addresses. Rotate a key in Stripe and update the connection when needed.

Read and write permits actions that move money or send email. Use a stable
`idempotency_key` for each intended POST and inspect the result before retrying
an ambiguous failure. Stripe can prune idempotency keys after 24 hours. On rate
limits, respect `retry-after` when provided and retry later with backoff; the
connector does not retry automatically.

Files must satisfy Stripe's purpose-specific size and format limits. Only files
with downloadable contents can be saved to a Houston session. The Files API does
not expose Atlas incorporation documents. Obtain those from [Atlas
Documents](https://dashboard.stripe.com/atlas/documents).

No OAuth application or Connect platform setup is needed. The connection acts on
the account owning its key; it does not accept a per-request connected-account
override. Atlas partner APIs, Connect administration, webhook delivery, Identity,
Issuing, Treasury, Tax and API v2 are outside this connector's scope.
