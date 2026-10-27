# Connect Vercel

Vercel connects with an access token. No developer app is required.

Choose the access level in Houston first: **Read-only** to review projects,
deployments, logs and domains, or **Read and write** to also redeploy, promote,
cancel builds and manage environment variables. Vercel tokens can always read and
write, so Houston enforces the access level you choose.

## Create an access token

1. Sign in to Vercel and open
   [Account Settings → Tokens](https://vercel.com/account/settings/tokens).
2. Under **Create Token**, name the token, for example, `Houston`.
3. Under **Scope**, choose the team to connect. A team token reaches only that
   team, which is the safest choice. Choose your personal account for its own
   projects, or **Full Account** for every team you belong to.
4. Choose an expiration and select **Create**, then copy the token. Vercel shows
   it only once.

See Vercel's [access token guide](https://vercel.com/docs/accounts/access-tokens).

## Add the connection

1. In your Houston organization, add the Vercel connector and choose its access
   level.
2. Leave **Team** empty for a team token or your personal account. With a **Full
   Account** token, enter the team's ID (in the team's **Settings → General**,
   starting with `team_`) or its URL slug.
3. Paste the token under **Access token**.
4. Save the connection and grant the appropriate organization members access.

## Advanced

### Troubleshooting

- **Requests fail with HTTP 403 "Not authorized".** The token expired, was
  revoked, or does not reach the team or project. Create a new token with the
  right scope.
- **Projects or deployments are missing.** A **Full Account** token without a
  **Team** reaches only your personal account. Enter the team, or create a team
  token.
- **Requests fail with a rate limit.** Vercel limits each kind of request per
  minute. Wait for the reset and try again.
- **You need to stop access.** Delete the token on the Tokens page, or remove the
  connection in Houston. Vercel also revokes tokens found in public code.
