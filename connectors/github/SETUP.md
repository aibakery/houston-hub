# Connect GitHub

Choose an access level, then either sign in with GitHub or paste a personal access
token. With **Connect with GitHub** you install Houston's app instead of creating
one.

1. Choose **Read-only** or **Read and write**.
2. Select **Connect with GitHub** and authorize Houston's GitHub App.
3. Install the app where your repositories live: open the Houston app's page on
   GitHub (the app name on the authorization screen links to it, at
   `github.com/apps/...`), select **Install** (or **Configure** if it is already
   installed), pick your account or organization, and choose **All repositories**
   or **Only select repositories**. Organization owners may need to approve it.

Houston sees public data plus the repositories where the app is installed, limited
to what your own GitHub account can do. Change the repository selection anytime in
[Installed GitHub Apps](https://github.com/settings/installations) or your
organization's **Settings → GitHub Apps**; no reconnect is needed.

## Advanced

### Use a personal access token

A token is useful for automation accounts or when you cannot install the app.
Choose **Personal access token** and paste a token created as follows.

**Fine-grained token** (recommended):

1. Open [New fine-grained personal access token](https://github.com/settings/personal-access-tokens/new).
2. Enter a **Token name**, choose an **Expiration**, and pick the **Resource owner**:
   your account or an organization (which may require an owner's approval).
3. Under **Repository access**, choose **All repositories** or **Only select
   repositories**.
4. Under **Permissions**, add these **Repository permissions**: **Actions**,
   **Commit statuses**, **Contents**, **Issues** and **Pull requests**, set to
   **Read-only** for a read-only connection or **Read and write** otherwise
   (**Metadata** is added as read-only automatically). For read and write, also add
   **Workflows** to edit workflow files, and **Administration** and **Repository
   creation** to create, fork or update repositories.
5. Optionally add **Members** (read-only) under **Organization permissions**, and
   **Email addresses** (read-only) and **Gists** (read and write) under **Account
   permissions**.
6. Select **Generate token** and copy it.

**Classic token**: in [New personal access token (classic)](https://github.com/settings/tokens/new),
tick `repo`, `workflow`, `read:org`, `gist`, `notifications` and `user:email`.
Classic tokens reach every repository you can access, and `repo` always allows
writes on GitHub's side; Houston still blocks writes on a read-only connection.
Notifications are only available with classic tokens, and check runs need a
classic token or **Connect with GitHub**: fine-grained tokens cannot read them.

### Troubleshooting

- **A repository is missing or returns "Not Found"**: GitHub hides private
  repositories you cannot access. Add the repository to the app installation or
  token, and check that an organization owner approved it. Organizations using SAML
  single sign-on require you to authorize the token for that organization
  (**Configure SSO** next to the token).
- **"Resource not accessible"**: the app or token lacks a permission; the error
  names the permissions GitHub expects.
- **Rate limits**: GitHub allows 5,000 requests per hour per user and fewer for
  searches; errors report when the limit resets.
- **Expired token**: create a new token and update the connection. Sign-ins with
  GitHub refresh automatically; if GitHub reports the authorization was revoked,
  connect again. Revoke Houston's access in
  [Authorized GitHub Apps](https://github.com/settings/apps/authorizations).
