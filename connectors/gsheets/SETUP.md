# Connect your Google account

1. Choose the access level:
   - **Read-only** to let agents read spreadsheets without changing anything.
   - **Read and write** to also let agents edit cells, add rows, create
     spreadsheets and change tabs and formatting.
2. Select **Connect with Google**, choose your account, and approve the
   permissions Google lists. If Google shows a checkbox per permission, tick
   them all: Houston refuses a partial grant.

Houston keeps your Google authorization on its server; agent scripts never see
it. The connection can open every spreadsheet your Google account can open, but
nothing else in your Drive; connecting Google Sheets does not grant access to
your other Google services.

## Advanced: changing access and troubleshooting

- To change the access level, edit the connection and connect with Google again.
  Google then asks for the new set of permissions.
- To revoke access, remove the connection in Houston, or remove Houston from
  [your Google Account's third-party connections](https://myaccount.google.com/connections).
- Google Workspace administrators can block third-party apps. If Google refuses
  the connection, ask your administrator to allow Houston.
- An agent that cannot open a spreadsheet may be using a link from **Publish to
  the web**. Share the spreadsheet's normal link instead, from the address bar
  while it is open.
- Excel files stored in Drive open in Sheets but cannot be read by agents.
  Convert one with **File > Save as Google Sheets** and share the new link.
