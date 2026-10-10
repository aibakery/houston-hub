# Connect your Notion account

In Houston, add the **Notion** connector from the Hub and choose an available
sign-in method. Choose **Read-only** to browse and query, or **Read and write** to
let agents create and change content.

## Connect with a token

1. Create an internal connection in [Notion's developer portal](https://www.notion.so/profile/integrations),
   or create a [personal access token](https://developers.notion.com/guides/get-started/personal-access-tokens).
2. For an internal connection, share the pages or databases through their
   **Connections** menu in Notion. A personal access token uses your own permitted access.
3. In Houston, choose **Internal connection or personal access token**, paste
   the token into **Token**, and add the connector.

## Connect with Notion (OAuth)

1. Create a public connection in [Notion's developer portal](https://www.notion.so/profile/integrations) and configure its capabilities.
2. Copy the **OAuth callback URL** already shown in the Houston setup form and
   add it to Notion's redirect URI list. You can copy it before entering any credentials.
3. Enter Notion's OAuth client ID and secret in Houston, then choose **Connect with Notion**.
4. Choose **Authorize account**, select the workspace
   and pages to share, and return to Houston.

Credentials stay on the Houston server and are never available to agent scripts.
Only the pages you share are accessible.

## Advanced: permissions, enterprise access and troubleshooting

### Permissions and tokens

Grant the content, comments and user capabilities you need in Notion. You can
change shared pages and revoke access from Notion's connection settings.

Do not paste tokens into an agent conversation or script. Some agent,
meeting-note and skills features require a personal access
token or additional Notion plan permissions.

### OAuth callback lifetime

Each Houston connection gets its own callback URL, even when you add Notion
multiple times to the same organization. Reopening unfinished setup within 24 hours
keeps the reserved URL. Cancelling setup discards it; abandoned reservations expire.
If you restart after cancellation or expiry, update Notion's redirect URI to the
new URL. Once connected, reauthorizing keeps the same callback URL.

### Enterprise organization bot

For organization administration, add a separate connection using **Enterprise
organization bot (Admin API)**. This requires an eligible Notion Enterprise
organization and an organization bot token with the appropriate
[Admin API scopes](https://developers.notion.com/reference/admin/scopes).
Ask your Notion organization administrator for access if needed.

Paste the organization bot token into **Token** and choose the access level.
This connection exposes organization administration features instead of page
content. Ordinary connection tokens and personal access tokens cannot replace an
organization bot token. Read-only access excludes administrative changes and
creating export jobs.

### If content is missing

Check that you chose the correct workspace, shared the page or database with the
connection, and granted the necessary capabilities in Notion. Houston's access
setting cannot grant permissions that Notion has not given your connection.

File links expire. Ask your agent to retrieve the file's owning page, block or
comment again to obtain a fresh link. Removing the connection from Houston does
not revoke its token in Notion; revoke the token in Notion when you no longer
want it used.
