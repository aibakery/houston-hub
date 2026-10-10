# Connect your Notion account

In Houston, select the registered **Notion** connector and choose an available
sign-in method. Choose **Read-only** to browse and query, or **Read and write** to
let agents create and change content.

## Connect with Notion

If **Connect with Notion** is available, select it and sign in to Notion. Choose
the workspace and pages you want to share, then approve access and return to
Houston. You do not need to create an OAuth application or enter client credentials.

Only the pages you authorize are accessible. You can change shared pages and
revoke access from Notion's connection settings.

## Internal connection or personal access token

1. Create an internal connection in [Notion's developer portal](https://www.notion.so/profile/integrations),
   or create a [personal access token](https://developers.notion.com/guides/get-started/personal-access-tokens).
2. Grant the content, comments and user capabilities you need. For an internal
   connection, share the pages or databases through their **Connections** menu
   in Notion. A personal access token uses your own permitted access.
3. In Houston, choose **Internal connection or personal access token**, paste
   the token into **Token**, select the access level, and add the connector.

Your token stays on the Houston server. Do not paste it into an agent conversation
or script. Some agent, meeting-note and skills features require a personal access
token or additional Notion plan permissions.

## Enterprise organization bot

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

## If content is missing

Check that you chose the correct workspace, shared the page or database with the
connection, and granted the necessary capabilities in Notion. Houston's access
setting cannot grant permissions that Notion has not given your connection.

File links expire. Ask your agent to retrieve the file's owning page, block or
comment again to obtain a fresh link. Removing the connection from Houston does
not revoke its token in Notion; revoke the token in Notion when you no longer
want it used.
