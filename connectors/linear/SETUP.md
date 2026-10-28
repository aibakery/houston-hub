# Connect Linear

Choose one way to connect:

- **Personal API key** is the quickest way to connect your own account. No
  developer app is required.
- **Connect with Linear** signs in through a Linear OAuth app that you create in
  your workspace. Creating the app needs a Linear workspace admin.

Choose the access level in Houston first: **Read-only** to review issues and
projects, or **Read and write** to also create and update issues and comment.

## Personal API key

1. In Linear, open
   [Settings → Account → Security & access](https://linear.app/settings/account/security).
2. Under **Personal API keys**, select **New API key** and name it, for example,
   `Houston`.
3. Choose the key's permissions: **Read** for **Read-only**, or **Read** and
   **Write** for **Read and write**. Optionally limit it to some teams.
4. Create the key and copy it. Linear shows the key only once.
5. In your Houston organization, add the Linear connector, choose **Personal API
   key** and paste the key.
6. Save the connection and grant the appropriate organization members access.

If you cannot create an API key, a workspace admin can allow it under
**Settings → Administration → API → Member API keys**.

## Connect with Linear

Each Houston connection has its own callback URL, so create an app for this
connection.

1. In Houston, add the Linear connector, choose **Connect with Linear** and copy
   the **OAuth callback URL** shown.
2. In Linear, open
   [Settings → Administration → API → OAuth applications](https://linear.app/settings/api/applications/new)
   and create a new application. Give it a name, such as `Houston`, and a
   developer name and URL.
3. Paste the callback URL under **Callback URLs**.
4. To connect from another Linear workspace than the one owning the app, turn on
   **Public**.
5. Create the application and copy its **Client ID** and **Client secret** into
   Houston's **OAuth client ID** and **OAuth client secret**.
6. Select **Authorize account**, sign in to Linear, choose the workspace and allow
   access.

**Read-only** asks Linear for the `read` permission, and **Read and write** for
`write`, which includes reading.

See Linear's [API keys](https://linear.app/docs/api-and-webhooks#api-keys) and
[OAuth](https://linear.app/developers/oauth-2-0-authentication) guides.

## Advanced

### Changing the access level

With **Connect with Linear**, switching access levels asks Linear for different
permissions, so authorize the connection again afterwards. An API key keeps the
permissions chosen when it was created: create a new key with **Write** when
moving to **Read and write**.

### Troubleshooting

- **Requests fail with a permission or "forbidden" error.** The API key lacks a
  permission or team, or your account cannot access that team. Create a new key
  with the permissions above, or ask a team admin for access.
- **Authorization fails with a redirect error.** The app's callback URL must match
  the one Houston shows exactly. Each Houston connection has its own callback URL.
- **Authorization fails for another workspace.** Turn on **Public** in the OAuth
  application's settings.
- **Requests fail with HTTP 401.** The key was revoked or the authorization was
  removed. Create a new key or authorize again.
- **Requests fail with a rate limit.** Linear limits each user's API requests per
  hour. Wait a few minutes and try again.
- **You need to stop access.** Revoke the key under **Security & access**, revoke
  the app under **Authorized applications**, or remove the connection in Houston.
