# Connect your Dropbox account

You need your own Dropbox app: it gives Houston an app key and secret, and lets
you decide which folders it can reach. Creating one is free and takes a few minutes.

1. In Houston, add the Dropbox connector and choose the access level:
   - **Read-only** to let agents browse and download without changing anything.
   - **Read and write** to also let agents upload, organize and share files.

   Then copy the **OAuth callback URL** shown.
2. Open the [Dropbox App Console](https://www.dropbox.com/developers/apps) and
   select **Create app**. Choose **Scoped access**, then the access type:
   **Full Dropbox** (recommended) for every file, or **App folder** to limit the
   connection to one folder Dropbox creates under **Apps**. An App folder app
   cannot work with shared folders or files shared with you. Name the app, for
   example `Houston for Acme`, and create it.
3. On the app's **Permissions** tab, tick every permission listed under
   [Permissions](#permissions) for both access levels, so you can change the access
   level later, and select **Submit**.
4. On the **Settings** tab, paste the callback URL under **OAuth 2 → Redirect
   URIs** and select **Add**. If other people will connect their own Dropbox
   accounts to this app, select **Enable additional users** under
   **Development users**.
5. Copy the **App key** and **App secret** from the **Settings** tab into Houston's
   **Dropbox app key** and **Dropbox app secret**.
6. Select **Connect with Dropbox**, sign in and allow access.

Houston keeps your Dropbox authorization on its server; agent scripts never see it.

## Permissions

For **Read-only**: `account_info.read`, `files.metadata.read`,
`files.content.read`, `sharing.read` and `file_requests.read`.

For **Read and write**, also: `files.metadata.write`, `files.content.write`,
`sharing.write` and `file_requests.write`.

See Dropbox's [OAuth guide](https://docs.dropboxapi.com/dropbox-api/docs/oauth) and
[permissions guide](https://docs.dropboxapi.com/dropbox-api/docs/developer-resources/developer-guide#app-permissions).

## Advanced

### Changing the access level

Switching access levels asks Dropbox for a different set of permissions, so
connect with Dropbox again after editing the connection.

### Dropbox teams

Agents work in your own Dropbox folder by default. On a Dropbox team with a team
space, a **Full Dropbox** app also lets them reach the team's folders.

### Troubleshooting

- **Dropbox shows "Invalid redirect_uri".** The app's redirect URI must match the
  callback URL Houston shows exactly. Each Houston connection has its own callback
  URL.
- **Dropbox shows an invalid scope error.** The app lacks a permission listed
  above. Tick it on the **Permissions** tab, select **Submit** and connect again.
- **Another person cannot connect.** Select **Enable additional users** on the
  app's **Settings** tab. A development app can link up to 500 accounts; once 50
  have connected, Dropbox asks you to
  [apply for production](https://docs.dropboxapi.com/dropbox-api/docs/developer-resources/developer-guide#production-approval)
  within two weeks.
- **You need to stop access.** Remove the connection in Houston, or disconnect the
  app under **Connected apps** in your
  [Dropbox security settings](https://www.dropbox.com/account/connected_apps).
