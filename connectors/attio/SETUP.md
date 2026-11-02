# Connect your Attio workspace

An Attio workspace admin creates the API key; no developer app is required.
API keys are available on every Attio plan and do not expire.

1. In Attio, click the menu beside your workspace name and select
   **Workspace settings**.
2. Open the **Developers** tab and click **+ New access token**.
3. Name the token, for example `Houston`.
4. Under **Scopes**, give **Read** access to what Houston may see. Leave write
   access off: the connector never changes your data.
   - `record_permission` and `object_configuration`: records and objects
     (required for almost everything).
   - `list_entry` and `list_configuration`: lists and their entries.
   - `note`, `task`, `comment`: notes, tasks and comment threads. Tasks also
     need `user_management`.
   - `user_management`: workspace members.
   - `meeting` and `call_recording`: meetings, recordings and transcripts.
   - `file`: file and folder details.
   - `email`: email metadata, if your workspace has access to it.
5. Save the token, then click it to copy the key.
6. In Houston, add the Attio connector and paste the key into its private
   **API key** field. Never paste the key into a chat or saved action.
7. Save the connection and grant the appropriate members access.

You can then ask about a company, its open deals, recent notes and meetings, or
anything else the key can read.

See Attio's [API key guide](https://attio.com/help/apps/other-apps/generating-an-api-key).

## Advanced

### Change what Houston can see

On the **Developers** tab, click the three dots beside the token, select
**Edit** and change its **Scopes**. The connection keeps working with the new
scopes; there is nothing to update in Houston.

### Troubleshooting

- **Something is missing or a request is refused**: the key lacks the scope for
  it. Add the read scope listed above.
- **Requests stop working**: the token was deleted. Create a new one and update
  the connection's **API key**.
- **Emails are unavailable**: Attio enables email access per workspace. Ask
  Attio support to enable it, then add the `email` scope.
