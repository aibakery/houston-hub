# Connect Wise

Requires a business account with 2-step login. Create tokens on the website.

1. In Wise, open **Accounting integrations → Custom integrations → API Tokens →
   Add new token**. Choose **Read-only**, or **Full access** for payments and changes.
2. Copy it into Houston's **Personal API token**, keep **Environment** on
   **Production**, choose the matching **Access** level and save.

If using **Allowed IPs**, allow Houston's server egress addresses, obtained from
your operator. [Official token guide](https://docs.wise.com/guides/developer/auth-and-security/personal-api-token).

## Advanced

> Outside the US, Canada, Australia, New Zealand, Singapore and Malaysia, personal
> tokens cannot complete the authentication required for funding transfers or
> exporting statements. Prepare transfers here, then pay or download statements in Wise.

If your business requires payment approvals, create and approve transfers in Wise;
API-created transfers are refused. Agents can still quote and add recipients.

For testing, create a token at [wise-sandbox.com](https://wise-sandbox.com) and choose
**Sandbox**. Tokens work only in their own environment. Revoke tokens from the same
API Tokens page and replace expired or revoked credentials in Houston.
