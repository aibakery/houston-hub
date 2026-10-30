# Connect your PostHog account

PostHog connects with a personal API key. No developer app is required. The key
acts as you, so it never reaches data your PostHog account cannot see.

## Create a personal API key

1. Sign in to PostHog and open **Settings → User → Personal API keys**: on
   [US Cloud](https://us.posthog.com/settings/user-api-keys) or
   [EU Cloud](https://eu.posthog.com/settings/user-api-keys).
2. Select **Create personal API key** and enter a **Label**, for example
   `Houston`. Choose an **Expiration** if you want the key to stop working on a
   set date.
3. Under **Organization & project access**, choose **Organizations** and select
   the organizations to connect. **All access** also works. **Projects** limits
   the key to chosen projects, but then Houston cannot list your organizations or
   projects, so you will need to give your agents project IDs yourself.
4. Under **Scopes**, give **Read** access to exactly these scopes, and no
   **Write** access:
   - **Insight** and **Query**, under **Product analytics**
   - **Person**, under **Events, people & data model**
   - **Feature flag**, under **Feature flags, experiments & surveys**
   - **Organization** and **Project**, under **Organization & account**
5. Select **Create key** and copy the key, which starts with `phx_`. PostHog shows
   it only once.

See PostHog's [personal API key guide](https://posthog.com/docs/api/personal-api-keys).

## Add the connection

1. In Houston, add the PostHog connector.
2. Under **Cloud region**, choose **US Cloud** if you open PostHog at
   `us.posthog.com`, or **EU Cloud** for `eu.posthog.com`.
3. Paste the key into the private **Personal API key** field. Never paste the
   key into a chat or saved action.
4. Save the connection and grant the appropriate members access.

You can then ask about your events, users, insights and feature flags.

## Advanced

### Project IDs

A project's ID is the number after `/project/` in PostHog's address, and it is
also shown in the project settings, under **Settings → Project**.

### Troubleshooting

- **Requests fail with HTTP 401**: the key is wrong, expired or deleted, or the
  connection uses the other cloud region. Check the region, or create a new key
  and update the connection's **Personal API key**.
- **Some requests fail with HTTP 403 "API key missing required scope"**: edit the
  key on the Personal API keys page and add the missing **Read** scope.
- **Listing organizations or projects fails with HTTP 403**: the key is limited
  to projects. Choose **Organizations** or **All access** under **Organization &
  project access**, or give your agents the project IDs.
- **Requests fail with HTTP 429**: PostHog limits each key to 240 analytics
  requests a minute and 1,200 an hour, and limits how much data queries read per
  hour. Wait and try again. Paid plans have a larger query budget.
- **Your organization doesn't allow personal API keys**: an organization admin
  can allow members to use them in the organization settings.
- **You need to stop access**: delete the key on the Personal API keys page, or
  remove the connection in Houston.
