1. Create a ClickHouse user for Houston with only the grants agents need. For
   read-only access, for example:

   ```sql
   CREATE USER houston IDENTIFIED BY 'choose-a-strong-password';
   GRANT SELECT ON analytics.* TO houston;
   ```

2. Make the HTTPS interface reachable from the internet; ClickHouse Cloud serves
   it on port 8443. Houston always verifies that the server certificate is
   issued by a public certificate authority for the host name you enter, and
   never connects without TLS.
3. In Houston, choose the access level, then enter the host, HTTPS port,
   database, username, and password, and select **Add connector**.

Your password stays on the Houston server.
