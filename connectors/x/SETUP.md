# Connect X

You need an **X developer account and an X developer app**. You can use an existing
app you manage or create one for Houston.

1. Sign in to the [X Developer Console](https://console.x.com/). Complete developer
   registration if prompted.
2. Open **Apps** and select your app from the left panel. If you do not have one,
   choose **Create App** and complete its details. Select or create a project if
   the Console asks which project the app should access.
3. In the app's credentials, find **App-Only Authentication → Bearer Token**.
   The Console uses **View API Keys** for the credentials view; some X guides
   still call it **Keys and tokens**. Open the individual app, rather than
   looking for that tab on the Console home page.
4. Generate the **Bearer Token** and copy it when shown. If you already saved this
   app's bearer token, you can reuse it. X only displays new credentials once.
5. Paste the token into **App bearer token** below, without a `Bearer ` prefix.
   Ensure your developer account has the API access and credits you need.

X bills usage to your developer account. Your token stays on Houston's server.

## Advanced: finding the right credential

Use the app-only **Bearer Token**, not **API Key and Secret**, **Access Token and
Secret**, or **Client ID and Secret**. This connection does not require a callback
URL or user sign-in authorization.

If a token already exists but you did not save it, **Regenerate** creates a
replacement. This invalidates the previous token, so update any other connections
using it. Regenerate only the bearer token, not the app's other keys.

If you cannot find your app, check the X account you signed in with. The Console
may list older apps under **Legacy Apps** with a link to their management page.

Official X references: [developer apps](https://docs.x.com/fundamentals/developer-apps),
[Developer Console](https://docs.x.com/fundamentals/developer-portal), and
[app-only bearer tokens](https://docs.x.com/fundamentals/authentication/oauth-2-0/bearer-tokens).
