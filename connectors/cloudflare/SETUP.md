# Connect Cloudflare

1. Open [API Tokens](https://dash.cloudflare.com/profile/api-tokens) and choose
   **Create Token → Create Custom Token**. Name the token `Houston`.
2. Grant the permissions below for the products agents may use; restrict
   **Account Resources** and **Zone Resources** to the intended account and zones.
3. Create and copy the token. In Houston, choose the matching access level,
   paste **API token** and save.

| Permission | Read-only | Read and write |
| --- | --- | --- |
| Account · Account Settings | Read | Read |
| Account · Workers Scripts | Read | Edit |
| Account · Cloudflare Pages | Read | Edit |
| Account · Workers R2 Storage | Read | Read |
| Zone · Zone | Read | Read |
| Zone · DNS | Read | Edit |
| Zone · Analytics | Read | Read |
| Zone · Cache Purge | — | Purge |

> Edit permissions allow more than Houston's supported changes. Houston still
> blocks changes on read-only connections. An IP filter must allow Houston's
> server addresses, not your device's.

[Official token guide](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/).

## Advanced

An account-owned token keeps working when its creator leaves. A Super Administrator
or someone allowed to create tokens can make one under **Manage Account → Account
API Tokens**, using the same permissions above.

For missing data or authorization errors, check the token's permissions, account
and zones. Analytics history depends on your plan. Rollbacks may fail if resources
used by the previous deployment no longer exist.
