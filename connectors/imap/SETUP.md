# Connect IMAP

1. Find your provider's IMAP host and create an app password if required.
   Houston needs implicit TLS, usually port **993**; STARTTLS on 143 is unsupported.
2. Enter **Host**, **Port**, **Username** (usually your email) and **Password**.
3. Choose **Read-only**, **Read and draft** to manage drafts for you to send, or
   **Read and write** to also organize mail. This connector cannot send email.
4. Keep **TLS mode** on **Verify certificate and host name (recommended)** and
   select **Add connection**. For a private server, see
   [Self-signed and private certificates](#self-signed-and-private-certificates).

> Use the dedicated Gmail or Fastmail connector for those services. Outlook.com
> and Microsoft 365 do not accept the password authentication this connector uses.

## Advanced

### Self-signed and private certificates

Paste the issuing authority's PEM certificate into **CA certificate**, including
its BEGIN/END CERTIFICATE lines. For a self-signed server, use its own certificate.
Never paste a private key. Houston then trusts only that authority.

| TLS mode | Verification |
| --- | --- |
| **Verify certificate and host name (recommended)** | Trusted authority and matching host |
| **Verify certificate only** | Trusted authority; does not check the host |
| **Encrypted, but doesn't check who the server is** | Encryption only; use solely for disposable test mailboxes |

> Without server verification, an interceptor can read your password and mail.
> An IP host must appear in the certificate's subject alternative names for full
> verification.

### Troubleshooting

Enable IMAP in your provider's settings and use an app password where required.
Check the TLS port, certificate chain and host name if the connection fails.
Moving messages requires the server's MOVE or UIDPLUS extension.
