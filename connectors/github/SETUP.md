# Connect GitHub

1. Choose **Read-only** or **Read and write** and select **Continue with GitHub**.
2. Authorize **OK Houston**, then [install or configure the app](https://github.com/apps/ok-houston)
   for the account/organization and repositories to share. An organization owner
   may need to approve it.

> Access is limited by your own GitHub permissions and the app's installations.
> Change shared repositories under [Installed GitHub Apps](https://github.com/settings/installations)
> without reconnecting.

## Advanced

### Personal access token

Choose **Personal access token** in Houston. Create a
[fine-grained token](https://github.com/settings/personal-access-tokens/new), select
its owner and repositories, and grant these repository permissions:

- **Actions**, **Commit statuses**, **Contents**, **Issues**, **Pull requests**:
  Read-only, or Read and write for a writable connection. Metadata is automatic.
- For workflow changes: **Workflows**. For creating/forking repositories:
  **Administration** and **Repository creation**.
- Optional: **Members** and **Email addresses** read access; **Gists** and
  **Starring** read/write access.

A [classic token](https://github.com/settings/tokens/new) instead needs `repo`,
`workflow`, `read:org`, `gist`, `notifications` and `user:email`. It covers all your
repositories and `repo` permits writes; Houston still enforces read-only access.
Notifications need a classic token; check runs need classic or app authorization.

### Missing repositories or access

Check installation/token repository selection, organization approval and SAML SSO
(**Configure SSO** on the token). Replace expired/revoked tokens or reconnect a
revoked app. Revoke app access in [Authorized GitHub Apps](https://github.com/settings/apps/authorizations).
