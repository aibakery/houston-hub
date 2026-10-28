# Connect your Notion account

You don't need to create a Notion integration: Houston provides one.

1. Choose **Read-only** to let agents search and read, or **Read and write** to
   also let them create and change content.
2. Keep **Connect with Notion** selected, choose **Authorize connector** and sign in.
3. Pick the workspace and the pages to share, then allow access.

Agents only see the pages you pick, including their subpages. To share more pages
later, edit the connection and authorize it again. Houston keeps your Notion
authorization on its server; agents never see it.

## Advanced

### Connect with a token

Use a token when **Connect with Notion** is unavailable, or to use a personal
access token's broader access.

1. Create an internal connection in [Notion's developer portal](https://www.notion.so/profile/integrations),
   grant the content, comment and user capabilities you need, and share pages
   through their **Connections** menu in Notion. Or create a
   [personal access token](https://developers.notion.com/guides/get-started/personal-access-tokens),
   which uses your own access.
2. Choose **Internal connection or personal access token** and paste it into
   **Token**. Never paste tokens into an agent conversation or script.

Some agent, meeting-note and skills features require a personal access token or
additional Notion plan permissions.

### Enterprise organization bot

For organization administration (legal holds, exports, analytics, groups, access
tokens and agent policies), add a separate connection with **Enterprise
organization bot (Admin API)** and paste an organization bot token with the
needed [Admin API scopes](https://developers.notion.com/reference/admin/scopes).
This requires an eligible Notion Enterprise organization; ordinary connection
tokens and personal access tokens cannot replace it. Read-only access
excludes administrative changes and creating export jobs.

### If content is missing

Check that you chose the right workspace, shared the page or database, and, for
an internal connection, granted the needed capabilities. Houston's access setting
cannot grant permissions that Notion has not given the connection.

File links expire; ask your agent to fetch the page, block or comment again for a
fresh link.

### Disconnect

Removing the connection from Houston does not revoke access in Notion. Also remove
Houston from your Notion connection settings, or revoke your token in Notion.
