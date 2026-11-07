# Connect Meta Business Suite

You need admin access to a business portfolio managing the Facebook Page, a Meta
app connected to that portfolio, and (for Instagram) a linked professional account.
Each Houston connection serves one Page.

1. [Create a Meta app](https://developers.facebook.com/apps/creation/) for your
   portfolio. Choose the Page, Messenger and optional Instagram use cases; use
   **API setup with Facebook Login** for Instagram. Add the permissions below.
2. In [Business settings](https://business.facebook.com/settings), open
   **Users → System users**. Create or select a system user and assign the app,
   Page and optional Instagram account with **Full control**.
3. Select **Generate token**, choose the app and permissions below, and select a
   non-expiring token if available.
4. In [Graph API Explorer](https://developers.facebook.com/tools/explorer/), paste
   that system user token and submit:

   ```text
   me/accounts?fields=name,access_token
   ```

5. Copy your Page's `access_token`. In the
   [Access Token Debugger](https://developers.facebook.com/tools/debug/accesstoken/),
   confirm **Type: Page** and check its expiry.
6. In Houston, choose **Read-only** or **Read and write**, enter the
   Page access token, and save the connection.

> Use the **Page token**, not the system user token. Customer conversations need
> Advanced Access, business verification and App Review. Until approved, messaging
> is limited to people with a role on the app, Page or portfolio.

## Permissions


For **Read-only**: `pages_show_list`, `pages_read_engagement`,
`pages_read_user_content`, `read_insights`, `pages_manage_metadata`,
`pages_messaging` and `business_management`; for Instagram, also
`instagram_basic`, `instagram_manage_comments`, `instagram_manage_insights` and
`instagram_manage_messages`.

For **Read and write**, also: `pages_manage_posts`, `pages_manage_engagement` and
`publish_video` when Meta offers it; for Instagram, `instagram_content_publish` and
`instagram_manage_contents`.

Some read-only permissions also allow changes: Meta requires `pages_manage_metadata`
to read conversations, adds `business_management` with the **Manage everything on
your Page** use case for business-owned Pages, and grants reading and replying to
messages together (`pages_messaging`, `instagram_manage_messages`). Leave out
messaging permissions if you do not need the inbox. On a **Read-only** connection
Houston blocks every write, whatever the token allows. See Meta's
[permissions reference](https://developers.facebook.com/docs/permissions).

## Advanced

- **Messaging:** request Advanced Access for `pages_messaging`,
  `pages_manage_metadata`, `pages_read_engagement` and, for Instagram,
  `instagram_basic` and `instagram_manage_messages`. In Instagram, enable
  **Allow access to messages** under **Connected tools**.
- **Expiry or changed permissions:** generate a new system user token, derive a
  new Page token and update Houston. Some businesses must use expiring tokens.
- **Missing Instagram:** link the professional account to the Page and assign it
  to the system user. Page insights require at least 100 followers.
- **appsecret_proof errors:** disable **Require app secret** in the app's
  **Advanced → Security** settings; Houston does not send app secret proofs.
- **Reply limits:** Meta generally permits replies within 24 hours. Hashtag search
  needs Instagram Public Content Access through App Review.
- **Revoke access:** remove the system user's Page access in Business settings.
