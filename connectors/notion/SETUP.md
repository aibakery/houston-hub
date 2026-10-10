# Set up Notion

In Houston's Hub, register repository `https://github.com/aibakery/houston-hub`,
revision `main`, manifest path `connectors/notion/houston.json`. It requires a deployment
with JSON OAuth token encoding, opaque path parameters and native `http.multipart` support. The registration
owns its optional OAuth client settings; a token-only registration needs no
publisher credentials.

## Internal connection or personal access token

1. Create a connection in [Notion's developer portal](https://www.notion.so/profile/integrations),
   or create a [personal access token](https://developers.notion.com/guides/get-started/personal-access-tokens).
2. Grant the content, comments and user capabilities your work requires. Share the
   pages/databases with an internal connection through Notion's Connections menu.
   A PAT acts with its owner's permitted access; feature and workspace policies
   still apply.
3. Add a connection in Houston, choose **Internal connection or personal access
   token**, paste the token into its secret field, and choose the access level.

Use `getSelf()` and a small `search({page_size=1})` as read-only smoke checks.
A 403/404 commonly means a missing capability or unshared content. Never paste
credentials into a Lua script. Tokens stay on the Houston server.

## Public connection (OAuth)

1. Create a public Notion connection and configure its capabilities.
2. Enter its OAuth client ID and client secret in the Houston registration's
   publisher settings. This enables **Connect with Notion**. Copy the exact
   callback URL Houston displays into the public connection's redirect URI list.
3. Add a connection, choose **Connect with Notion**, and authorize the pages to share.

Notion selects capabilities in the developer portal, not OAuth scope strings.
Houston uses HTTP Basic client authentication, a JSON token request and the
required Notion API version header. Refresh tokens, when returned, remain private
and are rotated by Houston. Disconnecting Houston is not a claim that the provider
credential has been revoked; revoke it through Notion's connection administration
when that is needed.

## Enterprise Admin API

Create an organization bot in Notion's organization administration and grant the
required [Admin API scopes](https://developers.notion.com/reference/admin/scopes).
Choose **Enterprise organization bot (Admin API)** in a separate Houston connection.
This API requires an eligible Enterprise organization and an organization bot;
ordinary internal/public connection tokens and PATs cannot substitute for it.
Read-only omits administrative mutations and export-job creation. Only the selected
authentication method's API surface appears in discovery and `help()`.

## Files and limits

Create an upload with `createFileUpload`, send a session file with `sendFileUpload`,
and attach its file-upload ID to content before it expires. For multipart uploads,
create with `mode="multi_part"` and `number_of_parts`, send each prepared part file
with a `part_number`, then call `completeFileUpload`. `external_url` mode imports
an external URL through Notion. The connector never collects file bytes in Lua.

`downloadFile` accepts fresh signed URLs from Notion's documented storage origins,
including the Notion-specific S3 buckets and regional file hosts listed in the
manifest. Arbitrary external URLs and redirects are not followed. Refresh expired
URLs by retrieving the owning object again. Admin export hosts can vary; an
unlisted storage origin requires reviewing and extending the manifest, never
sending a Notion bearer token to the storage service.

Operations return one page and never silently retry writes or wait for jobs.
Poll asynchronous tasks explicitly. `streamSession` stores the raw SSE stream in
a session file; Houston returns when the stream finishes and its execution limits
still apply. After a timeout, inspect the session and partial file before resuming
from a committed event ID. Cancellation cannot undo a remote write.
