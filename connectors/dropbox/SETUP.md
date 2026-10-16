# Connect your Dropbox account

You need your own Dropbox app: it gives Houston an app key and secret, and lets
you decide which folders it can reach. Creating one is free and takes a few minutes.

1. In Houston, add the Dropbox connector and choose the access level:
   - **Read-only** to let agents browse and download without changing anything.
   - **Read and write** to also let agents upload, organize and share files.
   - **Custom folder access** to edit the prefilled JSON mapping existing folders to
     `read-only` or `read-write`, for example
     `{"/Finance":"read-only","/Incoming":"read-write"}`. Everything else is
     denied. A more specific subfolder rule overrides its parent.

   Then copy the **OAuth callback URL** shown.
2. Open the [Dropbox App Console](https://www.dropbox.com/developers/apps) and
   select **Create app**. Choose **Scoped access**, then the access type:
   **Full Dropbox** (recommended) for every file, or **App folder** to limit the
   connection to one folder Dropbox creates under **Apps**. Shared folder/member
   operations and received-file listings require Full Dropbox; shared links and
   file requests work within App folder restrictions. Name the app, for
   example `Houston for Acme`, and create it.
3. On the app's **Permissions** tab, tick every permission listed under
   [Permissions](#permissions) for all access levels, so you can change the access
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

For **Read and write**, also: `files.content.write`,
`sharing.write` and `file_requests.write`.

**Custom folder access** requests the read permissions plus `files.content.write`.
Houston enforces each folder's permission, including read-only caller grants;
Dropbox OAuth cannot express these folder rules. You can create several Houston
connections for the same Dropbox account with different rules. Add each connection's
callback URL to the Dropbox app's redirect URIs.

See Dropbox's [OAuth guide](https://docs.dropboxapi.com/dropbox-api/docs/oauth) and
[permissions guide](https://docs.dropboxapi.com/dropbox-api/docs/developer-resources/developer-guide#app-permissions).

## Advanced

### Changing the access level

Switching access levels asks Dropbox for a different set of permissions, so
connect with Dropbox again after editing the connection.

### Dropbox teams

Agents work in your own Dropbox folder. Routes accepting namespace-qualified paths
can address accessible namespaces with `ns:<namespace_id>/...`, but ordinary
`/...` paths remain relative to your own folder. Full team-space traversal needs
Dropbox's `Dropbox-API-Path-Root` header, which this connector does not currently
set. See Dropbox's [team files guide](https://docs.dropboxapi.com/dropbox-api/docs/team-files).

### Custom folder rules

Use existing folder paths relative to your own Dropbox folder, with at most 64
rules. `"/"` grants the member-folder root. Dropbox resolves capitalization and
Unicode names. A folder must exist before it can be a rule or the parent of a new
file or folder. Two spellings of the same Dropbox folder are rejected.

Agents use ordinary paths and provide `options.path` when searching. IDs,
namespace aliases, shared links and revision download aliases are unavailable in
custom mode. Pagination still works: Houston returns protected continuation tokens
bound to the connection and its settings. Tokens from another connection, altered
tokens and tokens from an older configuration cannot widen access. Restart
pagination after updating the connector release, changing settings or reconnecting
Dropbox.

Choose explicit destinations: automatic renaming is unavailable. Moving or deleting
a folder containing a read-only rule is refused; copying into such a subtree is
also refused. Restore checks both the revision's original path and its destination.
Account-wide, sharing, file-request, batch and background-job operations are omitted
from custom connections. Read the connection's `help()` for its effective operations.

### Troubleshooting

- **Custom folder access is unavailable.** Edit the connection and correct its
  JSON object and permission names. Rules must use existing folder paths and
  `read-only` or `read-write`; invalid JSON or rules never grant broader access.
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
