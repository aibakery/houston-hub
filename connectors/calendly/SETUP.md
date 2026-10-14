# Connect Calendly

Choose one way to connect:

- **Personal access token** is the quickest way to connect your own account. No
  developer app is required.
- **Connect with Calendly** signs in through your own Calendly OAuth app. Use it
  when you prefer authorizing in the browser to copying a token.

Choose the access level in Houston first: **Read-only** to review meetings and
availability, or **Read and write** to also book, cancel and change things.

## Personal access token

1. Sign in to Calendly and open
   [Integrations → API & Webhooks](https://calendly.com/integrations/api_webhooks).
2. Under **Personal access tokens**, select **Get a token now** or
   **Generate new token**, and name it, for example, `Houston`.
3. Select the scopes for your access level, listed under
   [Scopes](#scopes), then select **Create token** and **Copy token**. Calendly
   shows the token only once.
4. In your Houston organization, add the Calendly connector, choose **Personal
   access token** and paste the token.
5. Save the connection and grant the appropriate organization members access.

## Connect with Calendly

You need a free Calendly developer account, separate from your Calendly login;
sign up at [developer.calendly.com](https://developer.calendly.com) with GitHub
or Google. Create an app for this connection: a Calendly app has one redirect URI,
and each Houston connection has its own callback URL.

1. In Houston, add the Calendly connector, choose **Connect with Calendly** and copy
   the **OAuth callback URL** shown.
2. In the Calendly developer portal, create an OAuth application. Choose **Web**
   as its kind and **Production** as its environment, and paste the callback URL as
   its **Redirect URI**.
3. Select every scope listed under [Scopes](#scopes) for both access levels, so
   you can change the access level later without editing the app.
4. Copy the **Client ID** and **Client Secret** into Houston's **OAuth client ID**
   and **OAuth client secret**. Calendly shows the secret only once.
5. Select **Authorize account**, sign in to Calendly and allow access.

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

### Plans and roles

Calendly still applies your plan and role. Booking meetings for invitees, webhooks
and meeting recaps need a paid plan. Organization-wide meetings, members and
webhooks need an organization admin or owner, and the activity log and sent
messages need an Enterprise admin.

### Changing the access level

With **Connect with Calendly**, switching access levels asks Calendly for
different scopes, so authorize the connection again afterwards. A personal access
token keeps the scopes chosen when it was created: create a new token with the
extra scopes when moving to **Read and write**.

### Troubleshooting

- **Requests fail with "Insufficient scope".** The token or app lacks a scope
  listed above. Create a new token with it, or create a new app with every scope
  listed above and update the connection's client ID and secret.
- **Authorization fails because scopes were not granted.** Allow every requested
  permission on Calendly's consent screen, and check that the app has every scope
  listed above.
- **Authorization fails with a redirect error.** The app's Redirect URI must match
  the callback URL Houston shows exactly. Each Houston connection has its own
  callback URL.
- **Requests fail with HTTP 401.** Calendly revokes tokens when your email,
  password or sign-in method changes. Create a new token or authorize again.
- **You need to stop access.** Delete the token on the API & Webhooks page or the
  app in the developer portal, or remove the connection in Houston.
