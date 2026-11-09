# Connect PostgreSQL

1. Create a database user with only the permissions agents need. For read-only
   access to existing tables:

   ```sql
   CREATE ROLE houston LOGIN PASSWORD 'choose-a-strong-password';
   GRANT CONNECT ON DATABASE app TO houston;
   GRANT USAGE ON SCHEMA public TO houston;
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO houston;
   ```

2. Make the server reachable from Houston with TLS enabled.
3. Enter **Host**, **Port**, **Database**, **Username** and **Password** in Houston.
4. Choose **Read-only** or **Read and write**, keep **TLS mode** on
   **Verify certificate and host name (recommended)**, and select **Add connection**.
   For a private certificate, see
   [Self-signed and private certificates](#self-signed-and-private-certificates).

## Advanced

### Self-signed and private certificates

For a private authority, paste its PEM certificate into **CA certificate**. For a
self-signed certificate, use the server certificate named by PostgreSQL's
`ssl_cert_file`. Include `-----BEGIN CERTIFICATE-----` and
`-----END CERTIFICATE-----`; never paste a private key. Houston then trusts only
that authority for this connection.

| TLS mode | Verification |
| --- | --- |
| **Verify certificate and host name (recommended)** | Trusted authority and matching host |
| **Verify certificate only** | Trusted authority; does not check the host |
| **Encrypted, but doesn't check who the server is** | Encryption only; use solely for disposable test data |

> Without server verification, someone intercepting the connection can read your
> password and data. For an IP host, full verification requires that IP in the
> certificate's subject alternative names.

### Troubleshooting

Check the host, port and firewall, and enable `ssl = on` in PostgreSQL. For an
untrusted certificate, supply the right CA and configure the server's intermediate
certificates. For a host mismatch, use the host named by the certificate.
