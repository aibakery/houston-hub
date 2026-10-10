1. Create a Redis user for Houston with only the commands agents need. For
   read-only access, allow read commands, `COMMAND INFO`, which Houston uses to
   confirm that a command is read-only, and `SELECT`, which opens a database
   number other than 0:

   ```
   ACL SETUSER houston on >choose-a-strong-password ~* +@read +command|info +select
   ```

   Redis servers without users can use the `default` username and the server
   password.
2. Make the server reachable from the internet over TLS. Houston always verifies
   that the server certificate is issued by a public certificate authority for
   the host name you enter, and never connects without TLS.
3. In Houston, choose the access level, then enter the host, port, database
   number, username, and password, and select **Add connector**.

Your password stays on the Houston server.
