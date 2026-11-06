# Connect Calendly

1. Open [API & Webhooks](https://calendly.com/integrations/api_webhooks) and generate
   a personal access token with the scopes below. Copy it when shown.
2. In Houston, choose **Personal access token**, paste it and select **Read-only**
   or **Read and write** to match the intended access. Save the connection.

## Scopes

For **Read-only**: `users:read`, `organizations:read`, `event_types:read`,
`availability:read`, `scheduled_events:read`, `locations:read`,
`routing_forms:read`, `groups:read`, `webhooks:read`, `contacts:read`,
`meeting_recaps:read`, `activity_log:read` and `outgoing_communications:read`.

For **Read and write**, also: `organizations:write`, `event_types:write`,
`availability:write`, `scheduled_events:write`, `scheduling_links:write`,
`shares:write`, `webhooks:write`, `contacts:write` and `meeting_recaps:write`.

See Calendly's [scope reference](https://developer.calendly.com/docs/authentication/scopes),
[personal access tokens](https://developer.calendly.com/docs/authentication/how-to-authenticate-with-personal-access-tokens)
and [OAuth app guide](https://developer.calendly.com/docs/authentication/creating-an-oauth-app).

## Advanced

### Your own OAuth app

1. In Houston, choose **Connect with Calendly** and copy **OAuth callback URL**.
2. At [developer.calendly.com](https://developer.calendly.com), create a **Web**,
   **Production** OAuth app with that exact **Redirect URI**. A developer account
   is separate from your Calendly login. Create one app per Houston connection.
3. Enable both scope lists above. Paste **OAuth client ID** and **OAuth client
   secret** into Houston, select **Authorize connector** and allow every permission.

Reauthorize when changing access. A token needs replacement to add scopes.
Calendly can revoke tokens when your sign-in details change.

### Plans and roles

Booking for invitees, webhooks and meeting recaps need a paid plan. Organization
meetings, members and webhooks need an admin/owner; activity logs and sent messages
need an Enterprise admin. Check scopes and callback matching if authorization fails.
