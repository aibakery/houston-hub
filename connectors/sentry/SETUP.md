# Connect Sentry

Sentry connects with an auth token for one organization on sentry.io. No
developer app is required. Self-hosted Sentry is not supported yet.

Choose the access level in Houston first: **Read-only** to review issues, events,
projects and releases, or **Read and write** to also resolve, ignore, assign and
comment on issues. Give the token the permissions for that level:

| Sentry permission | Read-only | Read and write |
| --- | --- | --- |
| Organization | Read (`org:read`) | Read (`org:read`) |
| Project | Read (`project:read`) | Read (`project:read`) |
| Issue & Event | Read (`event:read`) | Read & Write (`event:write`) |
| Member | Read (`member:read`) | Read (`member:read`) |

Leave every other permission at **No Access**. Houston also blocks every change
on read-only connections.

## Create a personal token

A personal token acts as you: it reaches what your Sentry role allows, and your
name appears on the comments and changes agents make.

1. Sign in to Sentry and open
   [Personal Tokens](https://sentry.io/settings/account/api/auth-tokens/) (also in
   the account menu at the top left).
2. Select **Create New Token** and enter a name, for example `Houston`.
3. Set the permissions from the table above. Sentry cannot change a personal
   token's permissions later, so choose them for the access level you need.
4. Select **Create Token** and copy the token, which starts with `sntryu_`.

See Sentry's [auth token guide](https://docs.sentry.io/account/auth-tokens/).

## Add the connection

1. In your Houston organization, add the Sentry connector and choose its access
   level.
2. Under **Data storage location**, choose where your organization keeps its
   data: **United States (US)** or **European Union (EU)**. Your organization's
   **Settings** page shows it under **Data Storage Location**.
3. Under **Organization**, enter your organization's slug: the `<slug>` in
   `https://<slug>.sentry.io` or `sentry.io/organizations/<slug>/`.
4. Paste the token under **Auth token**.
5. Save the connection and grant the appropriate organization members access.

## Advanced

### Use an internal integration instead

An internal integration's token belongs to the organization rather than to a
person, so it keeps working when its creator leaves, and its permissions can be
changed later. You need the Owner or Manager role.

1. In Sentry, open **Settings → Developer Settings** and select **Create New
   Integration**, then **Internal Integration**.
2. Enter a name, for example `Houston`, and set **Permissions** from the table
   above.
3. Select **Save Changes**. Copy the token from the integration's **Tokens**
   section and paste it under **Auth token** in Houston.

Changes and comments then appear under the integration's name.

### Organization tokens

Organization tokens (starting with `sntrys_`, under **Settings → Developer
Settings → Organization Tokens**) only carry Sentry's CI permissions. They can
read releases but not issues, events, projects or members, and cannot make
changes. Use a personal token or an internal integration instead.

### Troubleshooting

- **Requests fail with HTTP 401.** The token was revoked or mistyped. Create a
  new token and update the connection.
- **Requests fail with HTTP 403.** The token lacks a permission from the table
  above, or your Sentry role cannot see the project. For a personal token, create
  a new one with the right permissions; for an internal integration, edit its
  permissions.
- **Requests fail with HTTP 404 for every organization request.** Check the
  organization slug, and that **Data storage location** matches your
  organization's.
- **Commenting fails with HTTP 400 "You have already posted that comment."**
  Sentry refuses the same comment twice on one issue.
- **Requests fail with HTTP 429.** Sentry limits how often each token may call
  each kind of request. Wait a few seconds and try again.
- **You need to stop access.** Revoke the token in Sentry, or remove the
  connection in Houston.
