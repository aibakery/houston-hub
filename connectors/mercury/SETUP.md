# Connect your Mercury account

1. In Mercury, open **Settings → Tokens** at
   [API Tokens](https://app.mercury.com/settings/tokens) and create an API token.
   Use **Read Only** to check balances, transactions and SAFEs. If Tokens is
   unavailable, ask your Mercury organization admin for access.
2. In your Houston organization, add the Mercury connector and enter the complete
   token in its private **API token** field, including the `secret-token:` prefix.
   Keep **Access** set to **Read-only** for viewing data. Never paste the token
   into a chat or saved action.
3. Save the connection and grant the appropriate organization members access.
   Connect ChatGPT to that Houston organization workspace to use the account.

You can then ask for your available balances, recent transactions, SAFE signing
and payment progress, or statement PDFs. Mercury's token scopes and your account's
product eligibility determine which information is available.

## Advanced

### Payments and other changes

Choose **Read and write** in Houston and create a Mercury token with the scopes
needed for the actions you want. Mercury's **Read and Write** tokens require an IP
allowlist: add the Houston server's outbound IP addresses or ranges, obtained from
your Houston operator. Your own device's IP does not identify Houston's requests.

If you only want to queue payments for approval, Mercury supports a **Custom**
token with `RequestSendMoney` without an IP allowlist. Houston still requires
write access to create these requests. Approvals follow your Mercury policies and
are completed in Mercury; the connector does not expose an approval bypass.

Payment and transfer calls require an idempotency key. Reuse a key only for the
same intended payment, and check the outcome after a timeout before trying again.

### Agent card details

**Allow revealing agent card numbers and CVCs** defaults to off. Enable it only if
you need the documented Vault API for agent cards. Mercury does not allow this
endpoint to reveal ordinary card details. Treat its output as sensitive.

### Availability and token maintenance

This connector connects to production Mercury using an API token. Mercury's
separate OAuth integration program requires prior approval and is not needed to
connect your own account. Sandbox accounts use different tokens and hosts and
are not supported by this bundle.

Mercury may downgrade unused write permissions or delete inactive tokens after
45 days. If access stops, check token validity, scopes and IP allowlists in Mercury,
then update the connection's token as needed.

Statements, invoices and SAFE PDFs download directly through the API. Attachment
metadata may contain expiring signed download links; retrieve fresh metadata when
a link expires. Only virtual cards can be issued through the API, and cardholders
must already exist in Mercury.

See Mercury's [getting started guide](https://docs.mercury.com/docs/getting-started),
[token policies](https://docs.mercury.com/docs/api-token-security-policies), and
[API reference](https://docs.mercury.com/reference).
