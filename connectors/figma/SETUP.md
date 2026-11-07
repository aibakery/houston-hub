# Connect Figma

1. In Figma, open **Settings → Security → Personal access tokens → Generate new
   token**. Set an expiry and the scopes below, then copy the token.
2. In Houston, choose **Personal access token**, paste it, select **Read-only** or
   **Read and write**, and save.

> Personal tokens expire within 90 days. Replace them in Houston before expiry.
> Your Figma plan and seat determine API quotas.

## Scopes

For **Read-only**: `current_user:read`, `file_content:read`,
`file_metadata:read`, `file_versions:read`, `file_comments:read`,
`library_assets:read`, `library_content:read`, `team_library_content:read` and
`projects:read`.

For **Read and write**, also `file_comments:write`.

See Figma's [scopes](https://developers.figma.com/docs/rest-api/scopes/),
[personal access tokens](https://developers.figma.com/docs/rest-api/personal-access-tokens/)
and [OAuth apps](https://developers.figma.com/docs/rest-api/oauth-apps/) guides.

## Advanced

### Your own OAuth app

1. In Houston, choose **Connect with Figma** and copy **OAuth callback URL**.
2. Under [My apps](https://www.figma.com/developers/apps), create an app owned by
   your team/organization. Register the callback under **OAuth credentials →
   Add a redirect URL**, and save its client ID and secret when shown.
3. Enable both scope lists above. Publish it as **Private** for your team;
   other users need a reviewed public app. Draft apps work only for you and plan admins.
4. Enter **OAuth client ID** and **OAuth client secret** in Houston, select
   **Continue with Figma** and allow access.

Each connection has its own callback. Reauthorize after changing access; personal
tokens need replacement to add scopes. Missing team projects require membership
and `projects:read` permission.
