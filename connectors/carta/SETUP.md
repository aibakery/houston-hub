# Connect Carta

1. Choose **Read-only** or **Read and write** access.
2. Select **Connect with Carta** and sign in with your Carta account.
3. On Carta's consent screen, choose the companies, firms or portfolios to share,
   then allow access.

Houston keeps the connection signed in. Carta ends a sign-in that goes unused for
14 days; if requests start failing with an authorization error, select **Set up
again** and sign in.

## Advanced

### Use your own Carta app

Turn on **Use your own Carta app** to connect through an app you register with
Carta, either in Carta's playground (a shared test environment with sample data
that resets daily) or in production. Playground apps are self-serve. Production
apps need Carta's review and cannot be edited afterwards; adding permissions
later means submitting a new app.

1. Register at the [Carta Developer Portal](https://developers.app.carta.com/user/registration)
   (or **Login** with an existing Carta account), then click **Create App**.
2. Set **Grant type** to authorization code and add Houston's displayed callback
   URL under **Callbacks**.
3. Under **Scopes**, select every scope below. Houston requests the first list for
   read-only access and both lists for read and write access.
   - Read: `read_user_info`, `read_issuer_info`,
     `read_issuer_capitalizationtablesummary`,
     `read_issuer_stakeholdercapitalizationtable`, `read_issuer_shareclasses`,
     `read_issuer_stakeholders`, `read_issuer_securities`,
     `read_issuer_valuations`, `read_issuer_securitiestemplates`,
     `read_issuer_interests`, `read_issuer_draftsecurities`,
     `read_corporation_info`, `read_compensation_benchmarks`,
     `read_opencaptables`, `read_investor_firms`,
     `read_investor_funds`, `read_investor_investments`,
     `read_investor_capitalizationtables`,
     `read_investor_stakeholdercapitalizationtable`, `read_investor_securities`,
     `read_investor_cashbalances`, `read_investor_fundperformance`,
     `read_investor_partners`, `read_portfolio_info`,
     `read_portfolio_securities`, `read_portfolio_issuervaluations`,
     `read_portfolio_transactions` and `read_portfolio_fundinvestmentdocuments`.
   - Write: `readwrite_issuer_securities`, `readwrite_issuer_draftsecurities`,
     `readwrite_issuer_secondarytransactions`, `readwrite_draftissuers`,
     `readwrite_opencaptables`, `readwrite_file_upload`,
     `readwrite_investor_capitalcalls`, `readwrite_investor_carriedinterest` and
     `readwrite_investor_managementfees`.
4. Click **Submit**, then **View app details**, and enter the app's `client_id`
   and `client_secret` in Houston.
5. Select **Connect with your Carta app** for production, or **Connect with your
   Carta playground app** for the playground, and sign in. In the playground,
   pick the persona to simulate: Company editor for companies, Investor for firms,
   Employee for shareholders and Lawyer for Carta Launch.

To use a playground app in production, promote it with **Actions → Promote to
production** in the Developer Portal and complete Carta's
[production review](https://docs.carta.com/api-platform/guides/getting-started/migrate-to-production/).
Promotion creates a new production app: enter its `client_id` and `client_secret` in
Houston, then select **Set up again** and sign in with **Connect with your Carta app**.
Carta's fund accounting endpoints (capital calls, management fees, carried interest)
are in beta; ask your Carta representative to enable them for your app before
choosing read and write access.

### Troubleshooting

- **Requested OAuth scopes not granted**: the app lacks a scope above, or Carta
  granted fewer than requested. Add the scopes (a production app needs a new
  review) and sign in again.
- **ACCESS_TO_RESOURCE_RESTRICTED**: the company, firm or portfolio wasn't
  shared at sign-in. Select **Set up again** and share it.
- **MISSING_INTERNAL_PERMISSION**: your Carta role doesn't allow that data; ask a
  company or firm admin in Carta.
