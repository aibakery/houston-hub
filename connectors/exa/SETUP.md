# Connect Exa

Exa connects with an API key. You need an Exa account; no developer app is
required.

## Create an API key

1. Sign in to the [Exa dashboard](https://dashboard.exa.ai/), or create a free
   account.
2. If you belong to several Exa teams, choose the team that should pay for
   Houston's requests with the team switcher in the top-left corner. Every key
   spends its team's credits.
3. Open [API Keys](https://dashboard.exa.ai/api-keys) and create a key, for
   example named `Houston`. Copy it.

## Add the connection

1. In Houston, add the Exa connector.
2. Paste the key into **API key**.
3. Save the connection and grant the appropriate members access.

You can then ask for web research, for example recent articles on a topic from
chosen sites, the main points of a page, or pages similar to one you like.

## Advanced

### Control spending

Exa bills each search, page read and answer to your team's credits; see
[Exa pricing](https://exa.ai/docs/admin/pricing). On the
[API Keys](https://dashboard.exa.ai/api-keys) page you can give the Houston key
its own spending budget or a lower rate limit, and on the
[Billing](https://dashboard.exa.ai/billing) page you can add credits or turn on
auto recharge.

### Troubleshooting

- **"INVALID_API_KEY"**: the key was mistyped or deleted. Create a new key and
  edit the connection to paste it.
- **"NO_MORE_CREDITS", "API_KEY_BUDGET_EXCEEDED" or "TEAM_BUDGET_EXCEEDED"**:
  the team ran out of credits, or the key or team reached its spending budget.
  Add credits, or ask a team owner to raise the budget.
- **"FEATURE_DISABLED"**: your Exa plan does not include that kind of search.
- **"RATE_LIMIT_EXCEEDED"**: your team made more requests per second than its
  limit allows. Wait a moment and try again.
- **A page cannot be read**: some sites block crawlers or need a sign-in. Exa
  reports these pages individually without failing the others.

To stop access, delete the key on the API Keys page or remove the connection in
Houston. See Exa's [billing and rate limits](https://exa.ai/docs/admin/billing)
and [error codes](https://exa.ai/docs/admin/error-codes).
