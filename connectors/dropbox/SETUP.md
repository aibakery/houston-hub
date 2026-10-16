# Connect Dropbox

Choose your access level, then authorize your Dropbox account. No app setup is
needed for the standard sign-in.

## Advanced

### Use your own app

Enable **Use your own Dropbox app** to use an existing app or create one in the
[Dropbox App Console](https://www.dropbox.com/developers/apps):

1. Choose **Scoped access** and **Full Dropbox** (or **App folder** for a dedicated
   folder under Apps).
2. Under **Permissions**, enable `account_info.read`, `files.metadata.read`,
   `files.content.read`, `sharing.read`, `file_requests.read`, `files.content.write`,
   `sharing.write` and `file_requests.write`, then **Submit**. Houston requests
   only the permissions needed for your chosen access level.
3. Add Houston's displayed callback URL to **Settings → OAuth 2 → Redirect URIs**.
   Enter the app's **App key** and **App secret** in the form, then authorize.

Enable **additional users** in Settings if others will connect.

### Folder permissions

Custom access applies to existing folders. Unlisted folders are denied and the
most specific rule wins. Houston enforces these limits; Dropbox itself grants
broader app permissions. Sharing, file requests and batch operations are unavailable
in this mode. Restart any ongoing file listing after changing permissions.

### Limits and reconnecting

Uploads support files up to 150 MiB. Full team-space traversal is not supported.
Changing apps or access levels requires signing in again. Remove access anytime in
[Dropbox connected apps](https://www.dropbox.com/account/connected_apps).
