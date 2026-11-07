# Connect your Google account

1. Choose the access level:
   - **Read-only** to let agents read without changing anything.
   - **Read and draft** to also let agents prepare drafts for you to review and send from Gmail. Agents can also update or delete existing drafts. Google's consent screen mentions sending email, but Houston refuses every send request on this level.
   - **Read and write** to also let agents send and reply, manage drafts, and organize mail with labels and trash.
2. Select **Connect with Pipedream**, choose your Google account, and approve
   the permissions. Pipedream handles Google's sign-in and returns you to Houston.
   For production connections, you do not need to create a Pipedream account.

Publishers testing with Pipedream's development environment must also sign in to
Pipedream in the same browser. That environment supports up to ten external users;
publish with the production environment for the normal user sign-in experience.

Pipedream's Gmail application requests broad Gmail permissions, including sending
and managing mail, for every access level. Houston separately enforces the access
level you selected: read-only cannot write, and read and draft cannot send.

Direct Google sign-in is shown as a preview while Houston waits for Google
approval. Existing direct Google connections continue to work.

## Advanced: changing access and troubleshooting

- To change the access level, edit the connection and authorize it again.
  Reconnect the same mailbox; add a new connection to use a different mailbox.
  Pipedream may reuse your existing authorization without asking for consent again.
- If reconnecting reports multiple connected accounts, ask the connector
  publisher to resolve the extra accounts in Pipedream, then try again.
- Removing the connection in Houston stops Houston from using it. To revoke the
  provider's access too, open
  [your Google Account's third-party connections](https://myaccount.google.com/connections)
  and remove Pipedream, or Houston if you used direct Google sign-in. Removing a
  Houston connection does not automatically delete the account stored by Pipedream.
- Google Workspace administrators can block third-party apps. If Google refuses
  the connection, ask your administrator to allow the application shown on the
  consent screen.
