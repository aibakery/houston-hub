# Connect your Slack account

You only need a Slack account in the workspace you want to connect; there is no
Slack app to create. Some workspaces require an admin to approve Houston before you
can connect.

1. Choose the access level:
   - **Read-only** to let agents read your channels, direct messages
     and files.
   - **Read and write** to also let agents post, reply, edit or delete your
     messages, add reactions and share files as you.
2. Select **Add to Slack** and sign in to Slack.
3. Check the workspace shown in the top-right corner of Slack's permission page.
   Switch to the workspace you want to connect, then select **Allow**.

Houston keeps your Slack authorization on its server; agent scripts never see it.

## Advanced: workspaces, limits and troubleshooting

### Workspace approval

Some workspaces only allow approved apps. If Slack asks you to request approval,
send the request and wait for a workspace admin to approve Houston, then connect
again. Enterprise Grid organization-wide installations are not supported:
connect each workspace on its own.

### Several workspaces

Each connection covers the one workspace you chose. Add another Slack connection
for each additional workspace.

### Changing the access level

Switching between **Read-only** and **Read and write** asks Slack for different
permissions, so edit the connection and connect with Slack again.

### Reading long histories

Slack limits how quickly apps outside the Slack Marketplace can read channel
history and threads. Agents may need to wait between pages of a long channel,
so ask about a recent period rather than a whole history.

### Revoking access

Removing the connection in Houston deletes its stored authorization. To also
revoke it in Slack, remove Houston from your authorized apps in Slack's
[app management](https://slack.com/apps/manage) page. When you remove Houston in
Slack, or your Slack account is deactivated, Houston removes the connection and
deletes its authorization within about a day.

### Shared connections

Slack connections are personal: only the person who connected can use them, and
workspace admins can't share them. Each teammate connects their own Slack account.
