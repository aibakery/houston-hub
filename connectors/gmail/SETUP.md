# Connect your Google account

1. Choose the access level:
   - **Read-only** to let agents read without changing anything.
   - **Read and write** to also let agents send and reply, manage drafts, and organize mail with labels and trash.
2. Select **Connect with Google**, choose your account, and approve the
   permissions Google lists. If Google shows a checkbox per permission, tick
   them all: Houston refuses a partial grant.

Houston keeps your Google authorization on its server; agent scripts never see
it. Each Gmail connection asks only for its own permissions, so connecting
Gmail does not grant access to your other Google services.

## Advanced: changing access and troubleshooting

- To change the access level, edit the connection and connect with Google again.
  Google then asks for the new set of permissions.
- To revoke access, remove the connection in Houston, or remove Houston from
  [your Google Account's third-party connections](https://myaccount.google.com/connections).
- Google Workspace administrators can block third-party apps. If Google refuses
  the connection, ask your administrator to allow Houston.
