1. Create a MariaDB user for Houston with only the privileges agents need. For
   read-only access, for example:

   ```sql
   CREATE USER 'houston'@'%' IDENTIFIED BY 'choose-a-strong-password' REQUIRE SSL;
   GRANT SELECT ON app.* TO 'houston'@'%';
   ```

   A read-only connection accepts only reading statements, such as SELECT and
   SHOW, in a read-only session. An account with only read privileges keeps
   that true for any stored function a query calls.

2. Make the server reachable from the internet over TLS. Houston always verifies
   that the server certificate is issued by a public certificate authority for
   the host name you enter, and never connects without TLS.
3. In Houston, choose the access level, then enter the host, port, database,
   username, and password, and select **Add connector**.

Your password stays on the Houston server.
