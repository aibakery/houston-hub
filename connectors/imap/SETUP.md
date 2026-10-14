1. Find your provider's IMAP server name in its help pages, for example
   `imap.mail.me.com` for iCloud Mail or `imap.mail.yahoo.com` for Yahoo Mail.
   Houston connects with TLS, usually on port 993, and verifies the server
   certificate. Servers that offer only STARTTLS on port 143 are not supported.
2. Create an app password if your provider requires one. iCloud Mail, Yahoo
   Mail, Zoho Mail, and accounts with two-step verification usually do. Your
   regular password works only where the provider still allows it for IMAP.
3. In Houston, choose the access level:
   - **Read-only** to search, read, and download attachments.
   - **Read and write** to also flag messages, mark them read, move them,
     move them to the trash, and create folders.
4. Enter the IMAP server, port, username (usually your full email address), and
   password, then select **Add connector**.

Your password stays on the Houston server.

## Advanced: troubleshooting

- Gmail and Fastmail have dedicated connectors; use those instead. Outlook.com
  and Microsoft 365 accounts do not accept passwords over IMAP, so they cannot
  connect here.
- If sign-in fails, check that IMAP access is turned on in your provider's mail
  settings and that you used an app password where one is required.
- Moving messages needs a server with the IMAP MOVE or UIDPLUS extension, which
  most current servers have.
