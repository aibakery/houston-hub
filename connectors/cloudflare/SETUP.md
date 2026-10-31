# Connect Cloudflare

Cloudflare connects with an API token. No developer app is required. Either kind
of token works: a user token acts as you, and an account token belongs to the
account and keeps working when its creator leaves.

Choose the access level in Houston first: **Read-only** to review accounts,
zones, DNS records, Workers, Pages, R2 buckets and analytics, or **Read and
write** to also manage DNS records, purge the cache and roll back Workers and
Pages deployments. Give the token these permissions:

| Permission | Read-only | Read and write |
| --- | --- | --- |
| Account · Account Settings | Read | Read |
| Account · Workers Scripts | Read | Edit |
| Account · Cloudflare Pages | Read | Edit |
| Account · Workers R2 Storage | Read | Read |
| Zone · Zone | Read | Read |
| Zone · DNS | Read | Edit |
| Zone · Analytics | Read | Read |
| Zone · Cache Purge | Not needed | Purge |

Leave out the rows for products you don't use; agents then can't reach them.
Cloudflare's **Edit** permissions also allow changes that Houston never makes,
such as uploading Worker code or deleting projects. Houston allows only the
changes listed above, and none at all on read-only connections.

## Create a user token

1. Sign in to Cloudflare and open
   [API Tokens](https://dash.cloudflare.com/profile/api-tokens) (under **My
   Profile**).
2. Select **Create Token**, then **Get started** next to **Create Custom
   Token**.
3. Enter a name, for example `Houston`.
4. Under **Permissions**, add one row per line of the table above: choose
   **Account** or **Zone**, then the permission, then **Read**, **Edit** or
   **Purge**.
5. Under **Account Resources**, choose **Include** and the account to connect.
   Under **Zone Resources**, choose **Include** and **All zones from an
   account** with that account, or the specific zones agents may use.
6. Optionally restrict client IP addresses or set an expiry date. Houston's
   requests come from its servers, so leave the IP filter empty unless you
   know their addresses.
7. Select **Continue to summary**, then **Create Token**, and copy the token.
   Cloudflare shows it only once.

See Cloudflare's [token guide](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/).

## Add the connection

1. In your Houston organization, add the Cloudflare connector and choose its
   access level.
2. Paste the token under **API token**.
3. Save the connection and grant the appropriate organization members access.

## Advanced

### Use an account token instead

Account tokens act for the account rather than a person. You need the Super
Administrator role or permission to create API tokens.

1. In the [Cloudflare dashboard](https://dash.cloudflare.com), select the
   account, then **Manage Account → Account API Tokens**.
2. Select **Create Token** and set the name, permissions from the table above
   and the zones it covers.
3. Select **Continue to summary**, then **Create Token**, and paste the token
   under **API token** in Houston.

An account token reaches only its own account.

### Troubleshooting

- **Requests fail with HTTP 400 or 401 about the Authorization header.** The
  token was mistyped, revoked or has expired. Create a new token and update the
  connection.
- **Requests fail with HTTP 403 "Authentication error".** The token lacks a
  permission from the table above, or doesn't cover that account or zone. Edit
  the token in Cloudflare; the token itself stays the same.
- **No accounts or zones appear.** Check the token's **Account Resources** and
  **Zone Resources**, and that it has **Account Settings** and **Zone** read
  permissions.
- **Analytics fail with "cannot request data older than" or "time range is too
  large".** Your zone's plan limits how far back analytics go and how long a
  period one request may cover. Ask for a shorter or more recent period, or use
  daily instead of hourly figures.
- **Requests fail with HTTP 429.** Cloudflare allows 1,200 requests per five
  minutes for each token, fewer for analytics, and limits cache purges on Free
  plans to five per minute. Wait a few minutes and try again.
- **A Worker rollback is refused.** Cloudflare refuses a rollback when a KV
  namespace, R2 bucket or queue the earlier version uses no longer exists, or
  when the Worker's Durable Objects changed since that version. Check the
  Worker's **Deployments** in the Cloudflare dashboard.
- **You need to stop access.** Delete the token in Cloudflare, or remove the
  connection in Houston.
