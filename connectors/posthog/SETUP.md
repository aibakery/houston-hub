# Connect PostHog

1. Open **Settings → User → Personal API keys** in
   [US Cloud](https://us.posthog.com/settings/user-api-keys) or
   [EU Cloud](https://eu.posthog.com/settings/user-api-keys), then create a key.
2. Select the organizations to share. Grant **Read**, with no Write, for
   **Insight**, **Query**, **Person**, **Feature flag**, **Organization** and **Project**.
3. Copy the `phx_` key. In Houston, choose the matching **Cloud region**, paste
   **Personal API key** and save.

[Official API key guide](https://posthog.com/docs/api/personal-api-keys).

## Advanced

A key restricted to **Projects** cannot list organizations or projects. Supply
project IDs yourself; they appear after `/project/` in the URL and in project
settings. Organization admins may need to permit personal keys.

If access fails, check the region, expiry and missing read scopes. The key always
uses your own account's permissions. Self-hosted PostHog is unsupported.
