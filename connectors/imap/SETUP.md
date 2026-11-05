1. Find your provider's IMAP server name in its help pages, for example
   `imap.mail.me.com` for iCloud Mail or `imap.mail.yahoo.com` for Yahoo Mail.
   Houston connects with TLS, usually on port 993. Servers that offer only
   STARTTLS on port 143 are not supported.
2. Create an app password if your provider requires one. iCloud Mail, Yahoo
   Mail, Zoho Mail, and accounts with two-step verification usually do. Your
   regular password works only where the provider still allows it for IMAP.
3. In Houston, choose the access level:
   - **Read-only** to search, read, and download attachments.
   - **Read and write** to also flag messages, mark them read, move them,
     move them to the trash, and create folders.
4. Enter the IMAP server, port, username (usually your full email address), and
   password.
5. Keep **TLS mode** on **Verify certificate and host name (recommended)** for a
   mail provider's server. For a server with a self-signed or private
   certificate, such as a company mail server, see
   [Self-signed and private certificates](#self-signed-and-private-certificates).
6. Select **Add connector**.

Your password stays on the Houston server.

## Advanced

### Self-signed and private certificates

Each **TLS mode** encrypts the connection. They differ in how Houston checks that
it is talking to your mail server and not to someone in between:

| TLS mode | Houston checks | Use it for |
| --- | --- | --- |
| **Verify certificate and host name (recommended)** | The certificate comes from a trusted authority and names the server you entered | Every mailbox you care about |
| **Verify certificate only** | The certificate comes from the authority in **CA certificate**; any host name | A private authority whose certificates don't name the server you connect to |
| **Encrypted, but doesn't check who the server is** | Nothing about the certificate | Test mailboxes without real mail |

The recommended mode trusts public certificate authorities. To keep full checking
with a self-signed certificate or your own authority, paste its certificate, from
`-----BEGIN CERTIFICATE-----` to `-----END CERTIFICATE-----`, into **CA
certificate**. Houston then trusts only that authority for this connection. For a
self-signed certificate, paste the server's own certificate, such as the file
that Dovecot's `ssl_cert` setting names. Never paste a private key.

When the server is an IP address, the recommended mode requires the certificate
to list that address as an IP address in its subject alternative names. A
certificate whose common name or DNS name merely equals the address doesn't
match. Use **Verify certificate only** if the certificate doesn't list it.

**Encrypted, but doesn't check who the server is** lets anyone able to intercept
the connection impersonate your server and read your password and mail, so use
it only for test mailboxes.

### Troubleshooting

- Gmail and Fastmail have dedicated connectors; use those instead. Outlook.com
  and Microsoft 365 accounts do not accept passwords over IMAP, so they cannot
  connect here.
- If sign-in fails, check that IMAP access is turned on in your provider's mail
  settings and that you used an app password where one is required.
- **"The server's TLS certificate is not trusted".** The certificate comes from an
  authority Houston doesn't trust, or not from the one in **CA certificate**.
  Paste the right certificate into **CA certificate**. If the server uses a public
  authority, configure it to send its intermediate certificates too.
- **"The server's TLS certificate is not valid for" your server.** Enter a server
  name the error lists. Otherwise choose **Verify certificate only** and paste the
  certificate of the authority that issued the server's certificate into **CA
  certificate**.
- **"Does not accept TLS connections".** The port expects STARTTLS or no TLS.
  Use the server's implicit-TLS port, usually 993.
- Moving messages needs a server with the IMAP MOVE or UIDPLUS extension, which
  most current servers have.
