---
description: Work with Notion pages, databases, files, agents and workspace administration.
---

# Notion

Search shared pages, read and edit rich blocks or Markdown, manage databases and
data sources, query views, discuss work in comments, and upload or download files.
The connector also exposes meeting notes, custom emojis, agents, sessions, skills
and asynchronous tasks from Notion's current API.

Connect an internal connection token, a personal access token, or an OAuth public
connection. Choose **Read-only** to browse and query, or **Read and write** to
create and change content. Notion's own capabilities, page sharing, plan and beta
eligibility still apply. Agent sessions can take actions using their own enabled
tools; running a session requires read and write access in Houston.

Enterprise organization bots use a separate **Admin API** authentication option,
which exposes administration operations instead of workspace content operations:
legal holds, exports, analytics, permission groups, access tokens, MCP connections
and agent policies, permissions and credit limits.

The implementation preserves Notion's native field names, complete JSON responses,
nulls and pagination. Large transfers use native streaming. See [setup](SETUP.md)
and call the connection's `help()` for signatures, examples and provider limits.

API coverage is checked against Notion's official [Data API schema](https://developers.notion.com/openapi.json)
and [Admin API schema](https://developers.notion.com/openapi-adminApi.json):
61 content/agent/file operations and 40 administration operations, plus streamed
session and download helpers. Data API version: **2026-03-11**. Admin API version:
**2026-06-01**. Deprecated database APIs are replaced by data-source operations.
OAuth credential endpoints are managed separately from callable content operations:
Houston performs exchange and refresh; introspection and provider token revocation
remain application-administration tasks. Webhook subscriptions are configured in
Notion's developer portal; there is no subscription-management REST endpoint.

The icon uses the official Notion mark from the navigation on
[notion.com](https://www.notion.com/), retrieved 2026-10-10. Its SVG paths are
unchanged; the website's CSS fill is resolved to black. Notion owns the mark.
