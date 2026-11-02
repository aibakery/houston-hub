# Connect your WordPress site

You need a self-hosted WordPress site, version 5.6 or later, served over HTTPS,
and a WordPress user that can sign in to its dashboard. No plugin or developer app
is required.

We recommend a dedicated WordPress user for Houston, such as `houston`, with the
**Editor** role, or **Author** if agents should only manage their own posts. Avoid
an Administrator: an application password can do everything its user can.

1. Sign in to your WordPress dashboard as the user Houston should act as. To create
   a dedicated user, an administrator can open **Users → Add New User**, choose the
   role and select **Add New User**, then sign in as that user.
2. Open **Profile** in the dashboard menu (**Users → Profile** for administrators),
   and scroll to **Application Passwords**.
3. Enter a name such as `Houston` in **New Application Password Name**, and select
   **Add New Application Password**.
4. Copy the generated password now. WordPress shows it only once. The spaces are
   part of the display and can stay.
5. In your Houston organization, add the WordPress connector. Enter your site's
   domain in **Site domain**, such as `blog.example.com`, without `https://` or a
   path. Enter the WordPress **Username** and paste the **Application password**.
   Keep **Access** set to **Read-only** unless agents should make changes.
6. Save the connection and grant the appropriate organization members access.

You can then ask about recent posts, drafts waiting for review or comments to
moderate. Never paste the application password into a chat or saved action.

See WordPress's [Application Passwords guide](https://make.wordpress.org/core/2020/11/05/application-passwords-integration-guide/).

## Advanced

### Making changes

Choose **Read and write** in Houston. Agents can then create, edit, schedule,
publish and delete posts and pages, upload media, manage categories and tags, and
moderate comments, within the WordPress user's role. Publishing makes content
public immediately. Deleted posts, pages and comments go to the trash first, but
deleted media, categories and tags are removed permanently.

When the WordPress user is an Administrator, read-and-write connections can also
read the site's general settings, such as its title, time zone and admin email.
Read-only connections hide post passwords and commenters' and users' email and IP
addresses.

### Troubleshooting

- **The site domain was rejected.** Enter only the domain, such as
  `blog.example.com`, without `https://`, a path or a trailing slash.
- **Requests are redirected.** Enter the exact domain your site redirects to, for
  example `www.blog.example.com`. Houston does not follow redirects and connects
  only over HTTPS.
- **Requests fail with a JSON or "not found" error.** The REST API must be
  available at `https://<your domain>/wp-json/wp/v2`. In **Settings → Permalinks**,
  choose any structure other than **Plain**. Sites installed in a subdirectory,
  such as `example.com/blog`, and WordPress.com sites without plugins are not
  supported.
- **There is no Application Passwords section, or requests fail with
  "Application passwords are not available".** They require WordPress 5.6 or later
  and HTTPS that WordPress can detect: if a proxy or CDN ends HTTPS before your
  server, configure WordPress to recognize it. Some security plugins, such as
  Wordfence, and some hosts turn application passwords off; turn them back on in
  the plugin's settings, or ask your host.
- **Requests fail with HTTP 401.** Check the username and that the application
  password still appears under **Profile → Application Passwords**. Some
  hosts strip the `Authorization` header before it reaches WordPress; ask your host
  to pass it through. Security plugins that disable the REST API for logged-out
  visitors or block it from servers can also reject requests.
- **Requests fail with HTTP 403.** The WordPress user's role does not allow the
  change, for example an Author editing someone else's post.
- **Requests fail with HTTP 429 now and then.** WordPress itself doesn't limit its
  REST API, so the limit usually comes from your host's firewall or a security
  plugin. Houston already waits and retries short limits. Ask your host or plugin
  vendor to allow Houston's requests: they come from Houston's outbound IP address,
  available from your Houston operator, with the User-Agent
  `Houston (+https://ok-houston.com)`.
- **You need to stop access.** Revoke the application password under
  **Profile**, or remove the connection in Houston.
