# Connect Linear

1. Open [Security & access](https://linear.app/settings/account/security) and create
   a **Personal API key**. Grant **Read**, or **Read** and **Write**, and select teams.
2. In Houston, choose **Personal API key**, paste it, select the matching
   **Access** level and save.

If key creation is disabled, ask an admin to enable **Member API keys** under
**Administration → API**. [API key guide](https://linear.app/docs/api-and-webhooks#api-keys).

## Advanced

### Your own OAuth app

1. In Houston, select **Connect with Linear** and copy **OAuth callback URL**.
2. As a Linear admin, [create an OAuth app](https://linear.app/settings/api/applications/new)
   and register that exact URL under **Callback URLs**. Enable **Public** to allow
   other workspaces.
3. Enter **OAuth client ID** and **OAuth client secret** in Houston, then select
   **Continue with Linear**, choose the workspace and allow access.

Each connection has its own callback. Read-only requests `read`; writes request
`write`, which includes reading. Reauthorize after changing access. For an API key,
create a replacement with the new permissions. Check key team limits if data is
missing. [OAuth guide](https://linear.app/developers/oauth-2-0-authentication).
