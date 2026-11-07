# Connect WordPress

Requires self-hosted WordPress 5.6+ over HTTPS at the domain root.

1. Sign in as a dedicated user with the **Editor** role, or **Author** to manage
   only its own posts. Avoid an administrator account.
2. Open **Profile → Application Passwords**, name a new password `Houston`,
   select **Add New Application Password** and copy it. Displayed spaces can stay.
3. In Houston, enter **Site domain** without `https://` or a path, **Username** and
   **Application password**. Choose **Read-only** or **Read and write**, then save.

[Official application password guide](https://make.wordpress.org/core/2020/11/05/application-passwords-integration-guide/).

> The password inherits the user's role. Writes can publish immediately and email
> subscribers. Deleted media, categories and tags are permanent; posts, pages and
> comments go to Trash first.

## Advanced

The API must answer at `/wp-json/wp/v2`. Choose permalinks other than **Plain** and
use the final HTTPS domain; subdirectories and redirects are unsupported.
WordPress.com without plugins is unsupported.

If application passwords are unavailable, check HTTPS detection behind proxies
and security-plugin settings. For authentication failures, check the username,
password and forwarding of the Authorization header. Firewalls may need to allow
Houston's server egress addresses and `Houston (+https://ok-houston.com)` User-Agent.
Read-only connections hide post passwords and personal email/IP fields.
