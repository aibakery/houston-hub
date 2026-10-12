# Connect LinkedIn

You need a **LinkedIn developer app**. You can use an existing app you manage or
create one for Houston. Creating an app requires a LinkedIn Page for your
company; you or a Page admin must confirm the association.

1. In the [LinkedIn Developer Portal](https://www.linkedin.com/developers/apps),
   open your app or choose **Create app**.
2. On the app's **Products** tab, request **Sign In with LinkedIn using OpenID
   Connect**. To let agents post, also request **Share on LinkedIn**. Both are
   granted immediately.
3. Choose the access level in Houston: **Read-only** to read your basic profile,
   or **Read and write** to also publish and delete posts.
4. Copy the **OAuth callback URL** shown below. On the app's **Auth** tab, add it
   under **OAuth 2.0 settings → Authorized redirect URLs for your app**.
5. From the same **Auth** tab, copy the **Client ID** and **Primary Client
   Secret** into Houston's **OAuth client ID** and **OAuth client secret**.
6. Choose **Authorize account**, sign in to LinkedIn and allow access.

Your LinkedIn credentials stay on Houston's server and are never available to
agent scripts.

## Advanced: access, expiry and troubleshooting

### Reconnect every 60 days

LinkedIn access expires after 60 days and LinkedIn does not let ordinary apps
renew it automatically. When agents report that LinkedIn access expired,
reauthorize the connection in Houston. Reauthorizing keeps the same callback URL.

### Changing the access level

Switching between **Read-only** and **Read and write** asks LinkedIn for
different permissions, so authorize the connection again afterwards. LinkedIn
then replaces the previous authorization.

### If authorization fails

An **Invalid scope** error means the app does not have a product it needs:
check the **Products** tab for **Sign In with LinkedIn using OpenID Connect**
and, for **Read and write**, **Share on LinkedIn**. A redirect error means the
callback URL in the app's **Auth** tab does not exactly match the one Houston
shows. Each Houston connection has its own callback URL; if you cancelled setup
or it expired after 24 hours, update the app with the new URL.

To stop Houston posting as you, remove the connection in Houston and revoke the
app in LinkedIn's [permitted services](https://www.linkedin.com/psettings/permitted-services).

Official LinkedIn references: [developer apps](https://www.linkedin.com/developers/apps),
[3-legged OAuth](https://learn.microsoft.com/en-us/linkedin/shared/authentication/authorization-code-flow),
[Sign In with LinkedIn](https://learn.microsoft.com/en-us/linkedin/consumer/integrations/self-serve/sign-in-with-linkedin-v2)
and [Share on LinkedIn](https://learn.microsoft.com/en-us/linkedin/consumer/integrations/self-serve/share-on-linkedin).
