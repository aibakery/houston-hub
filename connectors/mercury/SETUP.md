# Connect Mercury

1. Create a **Read Only** token under [Settings → Tokens](https://app.mercury.com/settings/tokens).
   Ask your organization admin if this page is unavailable.
2. Paste the complete token, including `secret-token:`, into Houston's **API token**.
3. Choose **Read-only** and save, or configure writes as described below.

[Token guide](https://docs.mercury.com/docs/getting-started).

## Advanced

### Payments and changes

Choose **Read and write** and grant only the needed Mercury scopes. Mercury write
tokens require an IP allowlist containing Houston's server egress addresses,
obtained from your Houston operator. A **Custom** token with `RequestSendMoney`
can queue payments for approval without an IP allowlist. Approvals happen in Mercury.

> Enable **Allow revealing agent card numbers and CVCs** only when agents need
> those sensitive agent-card details; ordinary cards are not supported.

### Token maintenance

This connector supports production Mercury, not sandbox or OAuth connections.
Mercury may remove inactive tokens or downgrade unused write permissions after
45 days. Check scopes and IP restrictions if access stops.

[Token policies](https://docs.mercury.com/docs/api-token-security-policies).
