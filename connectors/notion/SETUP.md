# Connect Notion

1. Choose **Read-only** or **Read and write** in Houston.
2. Select **Continue with Notion**, choose your workspace and pages, and allow access.

> Agents can access the selected pages and their subpages. Reauthorize to share
> more. Notion's permissions and plan limits still apply.

## Advanced

### Connect with a token

Under **Other ways to connect**, choose **Internal connection or personal access
token**. Create an [internal connection](https://www.notion.so/profile/integrations),
grant needed content/comment/user capabilities and share pages through their
**Connections** menu. Alternatively, use a
[personal access token](https://developers.notion.com/guides/get-started/personal-access-tokens),
which uses your own access. Paste the token in Houston.

Some agent, meeting-note and skills features need a personal token or extra plan
permissions. If content is missing, check the workspace, shared pages and capabilities.

### Enterprise organization bot

Add a separate **Enterprise organization bot (Admin API)** connection with an
organization bot token and the required [Admin API scopes](https://developers.notion.com/reference/admin/scopes).
It requires an eligible Enterprise organization; ordinary tokens cannot replace it.
Read-only excludes administrative changes and export-job creation.

To revoke provider access, remove Houston in Notion or revoke the token;
deleting the Houston connection alone does not revoke it in Notion.
