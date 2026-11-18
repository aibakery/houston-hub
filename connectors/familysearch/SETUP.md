# Connect FamilySearch

1. Obtain a **public-client app key** through [FamilySearch Developer Support](https://developers.familysearch.org/main/docs/developer-support). Your key must be enabled for the environment you want to use; Production requires FamilySearch's compatibility approval.
2. Add a personal FamilySearch connection. Choose **Production** or **Beta (test data)** and select **Read** or **Write**.
3. Enter your **FamilySearch app key**, then choose **Sign in with FamilySearch** (or its Beta option). Copy Houston's displayed callback URL and ask FamilySearch Developer Support to register it for this key and environment.
4. Once the callback is registered, authorize the connection. Sign in to your FamilySearch account on FamilySearch's page, then return to Houston to finish setup.

> Arrange FamilySearch's [permission for AI use and contribution disclosure](https://developers.familysearch.org/main/docs/ai-disclosure-addendum) before using this connection with an AI agent. An app key alone does not establish that permission.

## Advanced

**Existing access token.** Select this method if you already have a token from the [FamilySearch OAuth flow](https://developers.familysearch.org/main/docs/authentication). Enter the token for the selected environment. Leave the app key blank when using a token; an app key is not itself an access token.

**Expired authorization.** FamilySearch tokens expire after 24 hours or 60 minutes without use. Normal accounts do not receive refresh tokens. Reauthorize an OAuth connection or replace its manual token when FamilySearch returns an expired-session error.

**App key and callback changes.** Keys and callback registrations are separate for Beta and Production. Houston displays a stable callback for this connection; reconnecting reuses it. This sign-in uses PKCE with a public client and does not require a client secret. See [API key management](https://developers.familysearch.org/main/docs/api-key-management).

**Write permissions.** Houston's access choice limits what the connection can do; it cannot grant additional FamilySearch permissions. Test contributions in Beta with disposable records before changing real family history.
