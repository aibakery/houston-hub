# Connect Meta Business Suite

Houston connects to one Facebook Page with a **Page access token** that never
expires. You make it once, from a system user of your business portfolio: a
business-owned account meant for integrations, so the connection does not depend
on anyone's personal Facebook login.

You need:

- a [business portfolio](https://business.facebook.com) that owns the Page or
  has access to it, and admin access to the portfolio;
- to use Instagram, an Instagram professional account linked to the Page;
- a Meta developer app connected to the portfolio. Creating one is free, and the
  steps below create it. App Review is not needed while the app and the Page belong
  to the same business portfolio.

Choose the access level in Houston first: **Read-only** to read posts, comments,
messages and insights, or **Read and write** to also publish, reply and moderate.

## 1. Create the Meta app

1. Open [Create an app](https://developers.facebook.com/apps/creation/) in Meta for
   Developers, and enter an app name, such as `Houston`, and your contact email.
2. Under **Use cases**, select **Manage everything on your Page** and **Engage with
   customers on Messenger from Meta**. For Instagram, also select **Manage messaging
   and content on Instagram** and then choose **API setup with Facebook Login**.
3. Under **Business**, select the business portfolio that manages your Page, then
   finish creating the app.
4. In the app dashboard, open each use case's **Customize** page and add the
   permissions listed under [Permissions](#permissions) for your access level.

## 2. Create a system user

1. Open [Business settings](https://business.facebook.com/settings) and select
   **Users** → **System users**.
2. Select **Add**, name the system user (for example `Houston`), choose the
   **Admin** role and select **Create system user**.
3. Select the system user, then **Assign assets**:
   - under **Apps**, select your app and turn on **Full control** (Manage app);
   - under **Pages**, select your Page and turn on **Full control**;
   - for Instagram, under **Instagram accounts**, select the account and turn on
     **Full control**.

## 3. Make the Page access token

1. With the system user selected, select **Generate token**. Choose your app, set
   the token expiration to **Never**, select the permissions listed under
   [Permissions](#permissions), and select **Generate token**. Copy the token: this
   is the system user's token, not yet the Page's.
2. Open the [Graph API Explorer](https://developers.facebook.com/tools/explorer/),
   paste the system user's token into **Access Token**, enter
   `me/accounts?fields=name,access_token` as the request and select **Submit**.
3. Copy the `access_token` shown next to your Page's `name`. This is the Page access
   token. Keep it secret: anyone holding it can act as your Page.
4. Optionally, paste it into the
   [Access Token Debugger](https://developers.facebook.com/tools/debug/accesstoken/):
   **Type** should be **Page** and **Expires** should be **Never**.

## 4. Add the connection in Houston

1. In your Houston organization, add the Meta Business Suite connector and choose
   the access level.
2. Paste the Page access token into **Page access token** and save the connection.
3. Grant the appropriate organization members access to it.

## Permissions

For **Read-only**: `pages_show_list`, `pages_read_engagement`,
`pages_read_user_content`, `read_insights`, `pages_manage_metadata`,
`pages_messaging` and `business_management`; for Instagram, also
`instagram_basic`, `instagram_manage_comments`, `instagram_manage_insights` and
`instagram_manage_messages`.

For **Read and write**, also: `pages_manage_posts` and `pages_manage_engagement`;
for Instagram, `instagram_content_publish` and `instagram_manage_contents`.

Meta grants reading and replying to messages together (`pages_messaging`,
`instagram_manage_messages`). On a **Read-only** connection Houston blocks every
write, whatever the token allows. See Meta's
[permissions reference](https://developers.facebook.com/docs/permissions).

## Advanced

### Changing the access level

The Page access token keeps the permissions its system user's token had when you
made it. Before moving to **Read and write**, generate a new system user token with
the extra permissions, make a new Page access token from it and update the
connection.

### Troubleshooting

- **Requests fail with "A Page access token is required".** The connection holds
  the system user's token. Make the Page access token from it (step 3) and update the
  connection.
- **Requests fail with code 10 or 200 naming a permission.** Add that permission to
  the app's use case, generate a new system user token with it, make a new Page
  access token and update the connection.
- **The Page has no Instagram account.** Link the Instagram professional account to
  the Page in Meta Business Suite, assign it to the system user, then make a new
  Page access token.
- **Instagram messages are missing.** In the Instagram app, open **Settings** →
  **Messages and story replies** → **Message controls** and turn on **Allow access
  to messages** under **Connected tools**.
- **Page insights fail.** Meta provides Page insights only for Pages with at least
  100 followers.
- **Requests fail with "appsecret_proof".** Turn off **Require app secret** in the
  app's **App settings** → **Advanced** → **Security**: Houston does not send app
  secret proofs.
- **Replies after 24 hours fail.** Meta allows messages outside the 24-hour window
  only with its Human Agent feature, which needs App Review; hashtag search similarly
  needs the Instagram Public Content Access feature.
- **The token stops working.** Removing the system user, its access to the Page or
  the app invalidates the Page access token. Make a new one and update the
  connection.
- **You need to stop access.** Remove the system user's access to the Page in
  **Business settings** → **System users**, or remove the connection in Houston.
