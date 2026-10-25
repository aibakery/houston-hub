# Connect your Granola account

Members of a **Business** or **Enterprise** workspace can create Granola API
keys; no developer app is required. On Enterprise, an admin chooses which note
access scopes members may use under **Settings → Workspace → General → API
access for members → Manage**.

1. Open the Granola desktop app, click your workspace name in the bottom-left
   corner and select **Settings**.
2. Go to **Connectors → API keys** and click **Create new key**.
3. Select the note access scopes the key should include, then click
   **Generate API Key**:
   - **Personal notes**: notes you own, notes shared with you, and notes in
     private folders shared with you.
   - **Public notes**: notes visible to everyone in the workspace, such as the
     Team space.
4. Copy the key, which starts with `grn_`.
5. In Houston, add the Granola connector and paste the key into its private
   **API key** field. Never paste the key into a chat or saved action.
6. Save the connection and grant the appropriate members access.

You can then ask about recent meetings, their summaries and attendees, or what
was said in a transcript.

See Granola's [API key guide](https://docs.granola.ai/help-center/sharing/integrations/granola-api).

## Advanced

### Workspace API keys

Workspace admins can create a key that belongs to the workspace instead of a
person under **Settings → Connectors → Workspace API keys**. It does not expire
and keeps working if its creator leaves. It reads public notes and the notes of
spaces whose **Allow Granola API access** setting is on. To change that setting
for an existing space, open the space, click **Integrations**, choose
**Granola API** and switch on **Allow access with a workspace API key**.
Workspace keys never read private notes.

### Troubleshooting

- **No notes are returned**: the key only reads notes matching its scopes, and
  Granola lists only notes that have a generated summary and transcript. Public
  notes must be in a folder visible to everyone, such as one in the Team space.
- **Requests stop working**: personal keys can expire, and revoked keys stop
  immediately. Create a new key and update the connection's **API key**.
- Audit and legal hold keys are separate Enterprise key types and do not work
  with this connector.
