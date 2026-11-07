# Connect Vercel

1. Open [Account Tokens](https://vercel.com/account/tokens), name a token, choose
   the team under **Scope** and select **All Projects**. Set an expiry and copy it.
2. Paste **Access token** into Houston and leave **Team** empty for a team token.
3. Choose **Read-only** or **Read and write**, then save.

> Vercel tokens can write; Houston enforces the selected access level. Write access
> includes environment variables, whose values may be secrets.

[Official token guide](https://vercel.com/docs/accounts/access-tokens).

## Advanced

A **Full Account** token reaches your personal account and teams. Leave **Team**
empty for personal projects, or enter a team ID/slug from **Settings → General**.
A token restricted to one project cannot list teams or domains. Check token scope
and expiry when data is missing, and replace expired or revoked tokens in Houston.
