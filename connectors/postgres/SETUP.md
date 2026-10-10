1. Create a PostgreSQL user for Houston with only the permissions agents need.
   For read-only access, for example:

   ```sql
   CREATE ROLE houston LOGIN PASSWORD 'choose-a-strong-password';
   GRANT CONNECT ON DATABASE app TO houston;
   GRANT USAGE ON SCHEMA public TO houston;
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO houston;
   ```

2. Make the server reachable from the internet over TLS. Houston always verifies
   that the server certificate is issued by a public certificate authority for
   the host name you enter, and never connects without TLS.
3. In Houston, choose the access level, then enter the host, port, database,
   username, and password, and select **Add connector**.

Your password stays on the Houston server.
