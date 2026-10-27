# Connect Figma

Choose one way to connect:

- **Personal access token** is the quickest way to connect your own account. No
  developer app is required. Figma tokens expire after at most 90 days.
- **Connect with Figma** signs in through a Figma OAuth app that you create. A
  new app works for members of the team or organization that owns it; people
  outside it need the app published, which Figma reviews.

Choose the access level in Houston first: **Read-only** to read files and
comments, or **Read and write** to also post comments and reactions.

## Personal access token

1. In Figma, open the account menu, select **Settings** and open the **Security**
   tab.
2. Under **Personal access tokens**, select **Generate new token** and name it,
   for example, `Houston`.
3. Choose an expiration and the scopes listed under [Scopes](#scopes) for your
   access level, then select **Generate token** and copy it. Figma shows the
   token only once.
4. In your Houston organization, add the Figma connector, choose **Personal access
   token** and paste the token.
5. Save the connection and grant the appropriate organization members access.

When the token expires, generate a new one and update the connection.

## Connect with Figma

Each Houston connection has its own callback URL, so create an app for this
connection.

1. In Houston, add the Figma connector, choose **Connect with Figma** and copy
   the **OAuth callback URL** shown.
2. Open [My apps](https://www.figma.com/developers/apps), select **Create a new
   app**, name it, for example, `Houston`, and choose the team or organization
   that owns it.
3. Add the callback URL as the app's redirect URL.
4. Select every scope listed under [Scopes](#scopes) for both access levels, so
   you can change the access level later without editing the app.
5. Copy the **Client ID** and **Client secret** into Houston's **OAuth client ID**
   and **OAuth client secret**. Figma shows the secret only once.
6. Select **Authorize account**, sign in to Figma and allow access.

## Scopes

For **Read-only**: `current_user:read`, `file_content:read`,
`file_metadata:read`, `file_versions:read`, `file_comments:read`,
`library_assets:read`, `library_content:read`, `team_library_content:read` and
`projects:read`.

For **Read and write**, also `file_comments:write`.

See Figma's [scopes](https://developers.figma.com/docs/rest-api/scopes/),
[personal access tokens](https://developers.figma.com/docs/rest-api/personal-access-tokens/)
and [OAuth apps](https://developers.figma.com/docs/rest-api/oauth-apps/) guides.

## Advanced

### Changing the access level

With **Connect with Figma**, switching access levels asks Figma for different
scopes, so authorize the connection again afterwards. A personal access token
keeps the scopes chosen when it was generated: generate a new token with
`file_comments:write` when moving to **Read and write**.

### Troubleshooting

- **Requests fail with HTTP 403 "Invalid token".** The token expired, was revoked
  or lacks a scope. Generate a new token, or authorize again.
- **Requests fail with HTTP 429.** Figma limits file reads and exports per minute,
  and View and Collab seats or the Starter plan get only a few a month. Wait as
  Figma asks, or use a Full or Dev seat.
- **Authorization fails with a redirect error.** The app's redirect URL must match
  the callback URL Houston shows exactly. Each Houston connection has its own
  callback URL.
- **Team projects are missing.** Your account must be a member of the team, and
  the token or app needs `projects:read`.
- **You need to stop access.** Revoke the token under **Security**, delete the app
  in My apps, or remove the connection in Houston.
