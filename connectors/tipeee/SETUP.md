# Connect Tipeee

1. Sign in to your creator account at [Tipeee](https://en.tipeee.com/), and open
   your creator dashboard.
2. Open your browser's developer tools. In **Application → Local Storage →
   https://en.tipeee.com**, locate `access_token`. On Firefox the equivalent is
   **Storage → Local Storage**. Use your actual Tipeee language origin if different.
   Copy the token's value; remove surrounding JSON quotes if the browser displays
   a quoted string. If it is not present, reload the signed-in dashboard and
   inspect a request to `api.tipeee.com` in **Network**: its query contains
   `access_token`. Copy only that value, not the complete URL.
3. In Houston, add the Tipeee connection, select **Session access token**, and
   paste the value into **Tipeee access token**. Keep the token in this secret field;
   do not paste it into scripts, chat or screenshots.
4. Choose **Read-only**, or **Read and write** if you need creator mutations,
   messages, payouts, account/project discovery, inbox threads, widget links or tipper exports. Save the connection.
5. Call `help()`, then `listRewards({project='your-project-slug'})` to check
   access using the slug from your creator page URL. With read-write access,
   `getMe()` also discovers your projects and canonical username; `getProject()`
   returns the project details. These discovery endpoints require read-write
   because their responses can carry a separate streaming credential.

## Advanced

This is an unofficial session-token integration, not a provider-issued developer
API key or a registered OAuth application. No developer console, self-service
OAuth registration, verified code-exchange contract or refresh mechanism was
found. No OAuth scopes need selecting. Houston injects `access_token` in the
upstream query on its server because the observed API requires it; connector
code never receives the account token. Tipeee and its infrastructure may log
query URLs.

Token lifetime is undocumented. If requests fail with 400 code `00004` or 403
access denied, sign in again, copy the current session token and update the
connection. Confirm that your account owns the project and that its slug is
correct. Payouts additionally require Tipeee's payout eligibility and completed
provider setup. Rate limits are undocumented; honor a returned `Retry-After`.

Use the [official general API docs](https://api.tipeee.com/api/doc/default)
for the documented subset. The [partner API](https://api.tipeee.com/api/doc/partner)
is a different integration for tippers and does not document creator management.
Creator fields were inspected in website release `20261022134411`; upstream
changes may require updating the connector. Do not automatically repeat a timed-out
publication, payment, message or upload: check its outcome first.
