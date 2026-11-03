1. Create a PostgreSQL user for Houston with only the permissions agents need.
   For read-only access, for example:

   ```sql
   CREATE ROLE houston LOGIN PASSWORD 'choose-a-strong-password';
   GRANT CONNECT ON DATABASE app TO houston;
   GRANT USAGE ON SCHEMA public TO houston;
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO houston;
   ```

2. Make the server reachable from the internet with TLS turned on. Houston never
   connects without TLS.
3. In Houston, choose the access level, then enter the host, port, database,
   username, and password.
4. Keep **TLS mode** on **Verify certificate and host name (recommended)** when
   your server has a certificate from a public certificate authority, such as a
   managed database's. For any other certificate, see
   [Self-signed and private certificates](#self-signed-and-private-certificates).
5. Select **Add connector**.

Your password stays on the Houston server.

## Advanced

### Self-signed and private certificates

Each **TLS mode** encrypts the connection. They differ in how Houston checks that
it is talking to your server and not to someone in between:

| TLS mode | Houston checks | Use it for |
| --- | --- | --- |
| **Verify certificate and host name (recommended)** | The certificate comes from a trusted authority and names the host you entered | Production data |
| **Verify certificate only** | The certificate comes from the authority in **CA certificate**; any host name | A private authority whose certificates don't name the host you connect to |
| **Encrypted, but doesn't check who the server is** | Nothing about the certificate | Test and demo databases without sensitive data |

The recommended mode trusts public certificate authorities. To keep full checking
with a self-signed certificate or your own authority, paste its certificate, from
`-----BEGIN CERTIFICATE-----` to `-----END CERTIFICATE-----`, into **CA
certificate**. Houston then trusts only that authority for this connection. For a
self-signed certificate, paste the server's own certificate, found in the file
that PostgreSQL's `ssl_cert_file` setting names. Never paste a private key.

When the host is an IP address, the recommended mode requires the certificate to
list that address as an IP address in its subject alternative names. A
certificate whose common name or DNS name merely equals the address doesn't
match. Use **Verify certificate only** if the certificate doesn't list it.

**Encrypted, but doesn't check who the server is** works like `psql` with
`sslmode=require`. Anyone able to intercept the connection could impersonate
your server and read your password and data, so use it only for databases
without sensitive data.

### Troubleshooting

- **"The server's TLS certificate is not trusted".** The certificate comes from an
  authority Houston doesn't trust, or not from the one in **CA certificate**.
  Paste the right certificate into **CA certificate**. If the server uses a public
  authority, configure it to send its intermediate certificates too.
- **"The server's TLS certificate is not valid for" your host.** Enter a host name
  the error lists. Otherwise choose **Verify certificate only** and paste the
  certificate of the authority that issued the server's certificate into **CA
  certificate**.
- **"Does not accept TLS connections".** Turn on TLS on the server (`ssl = on` in
  `postgresql.conf`), and check that the port is PostgreSQL's.
- **"Could not connect".** Check the host and port, and that the server and its
  firewall accept connections from the internet.
