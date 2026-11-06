# Connect Stripe

1. In the [Stripe Dashboard](https://dashboard.stripe.com/), select the account
   and live or sandbox environment. Use a sandbox for testing.
2. Under [API keys](https://dashboard.stripe.com/apikeys), create a restricted
   key starting with no permissions. Grant **Read** only for needed resources,
   or **Write** where agents should make changes. Related objects may need
   their own permissions.
3. Paste the `rk_test_` or `rk_live_` key into Houston's **Stripe API key**, choose
   **Read-only** or **Read and write**, and save. A secret `sk_` key also works;
   a publishable `pk_` key does not.

> Live write access can move money and send email. The key's permissions and
> account eligibility still apply.

[Official restricted key guide](https://docs.stripe.com/keys/restricted-api-keys).

## Advanced

If you restrict the key by IP, allow Houston's server egress addresses. Check the
account, environment, expiry and permissions when data is unavailable; replace
rotated keys in Houston. No OAuth app or Connect platform setup is needed.
Atlas incorporation documents remain in the [Atlas Dashboard](https://dashboard.stripe.com/atlas/documents).
