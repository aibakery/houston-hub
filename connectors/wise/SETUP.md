# Connect your Wise account

You need a Wise business account with 2-step login turned on. Wise documents
personal API tokens for business accounts; tokens are created only on the Wise
website, not in the app. No developer application or OAuth setup is needed.

1. Sign in to your business account at [wise.com](https://wise.com) and go to
   **Your Account** → **Connect and manage apps** → **API tokens**. The direct link
   is [API tokens](https://wise.com/settings/api-tokens); newer menus may name the
   section **Integrations and tools**.
2. Select **Add new token** and complete the 2-step verification.
3. Name the token Houston and choose its access level:
   - read only, to check balances, activity and transfers;
   - full, only if agents should prepare or send payments.
4. Copy the token. Wise shows it only once.
5. In Houston, add the Wise connector. Choose **Read-only** or **Read and write**
   under **Access** to match the token, keep **Environment** on **Production**,
   and paste the token into **Personal API token**. Never paste the token into a
   chat or saved action.
6. Save the connection and grant the appropriate members access. Start by asking
   for your profiles and balances.

See Wise's [personal API token guide](https://docs.wise.com/guides/developer/auth-and-security/personal-api-token).

## Advanced

### Funding transfers and statements

For accounts based outside the US, Canada, Australia, New Zealand, Singapore and
Malaysia, Wise requires strong customer authentication to fund transfers and to
export balance statements, and this connector cannot complete it. Those
requests fail with a message saying so. Agents can still quote, add recipients and
draft transfers or batches; open the transfer in the Wise app or website to pay it.
Download statements from Wise directly.

### Payment approvals

If your business account requires payment approvals (set in Wise's settings),
Wise rejects transfers created through the API with a missing-approval error.
Agents can still quote and add recipients; create and approve the transfer in
Wise, or change your approval settings.

### Sandbox

To try payments without real money, create a sandbox account at
[wise-sandbox.com](https://wise-sandbox.com), create a token in its settings the
same way, and set **Environment** to **Sandbox**. Production tokens do not work
in the sandbox, and sandbox tokens do not work in production.

### Troubleshooting

- **401 invalid_token**: the token was revoked, mistyped or belongs to the other
  environment. Create a new token and update the connection.
- **403 Forbidden**: the token is read only, the profile belongs to someone else,
  or the request needs strong customer authentication (see above).
- **429**: Wise rate limits each user. Wait for the time Wise reports and try again.

To revoke access, open [API tokens](https://wise.com/settings/api-tokens) and
choose **Revoke** next to the token; it stops working immediately.
