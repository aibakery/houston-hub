# Connect Sentry

1. Open [Personal Tokens](https://sentry.io/settings/account/api/auth-tokens/),
   choose **Create New Token**, and grant permissions below. Copy the token.
2. In Houston, choose **Data storage location** to match your organization's
   **Settings → Data Storage Location**.
3. Enter the **Organization** slug from `<slug>.sentry.io`, paste **Auth token**,
   choose the matching access level and save.

| Permission | Read-only | Read and write |
| --- | --- | --- |
| Organization | `org:read` | `org:read` |
| Project | `project:read` | `project:read` |
| Issue & Event | `event:read` | `event:write` |
| Member | `member:read` | `member:read` |

Leave other permissions at **No Access**. Personal token permissions cannot be
edited later. [Official token guide](https://docs.sentry.io/account/auth-tokens/).

## Advanced

An Owner or Manager can instead create an **Internal Integration** under
**Settings → Developer Settings**, assign the same permissions and use its token.
It belongs to the organization, survives its creator leaving, and allows later
permission changes. Comments appear under the integration's name.

Organization CI tokens (`sntrys_`) lack the necessary issue access. Self-hosted
Sentry is unsupported. For missing data, check the region, slug, token permissions
and your account's project access.
