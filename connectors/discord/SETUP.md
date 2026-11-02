# Connect a Discord server

There is no Discord app or bot to create: Houston adds its own bot to your
server. You need the **Manage Server** permission in the server you want to
connect (server owners and administrators have it).

1. Choose the access level:
   - **Read-only** to let agents read and search the server's channels and
     threads, and look up members and roles.
   - **Read and write** to also let agents post, reply, start threads, react,
     and edit or delete the bot's own messages.
2. Select **Continue with Discord** and sign in to Discord if asked.
3. Under **Add to Server**, choose the server to connect, then select
   **Continue**. Only servers where you have **Manage Server** are listed.
4. Review the permissions and select **Authorize**.

The connection is named after your server. Houston keeps its Discord
credentials on its server; agent scripts never see them.

## Advanced: permissions, several servers and removal

### What the bot's permissions mean

Discord asks you to grant the same permissions at either access level, because
they belong to the bot in your server rather than to one connection:

- **View Channels** and **Read Message History** to read channels, threads and
  past messages.
- **Send Messages** and **Send Messages in Threads** to post and reply.
- **Create Public Threads** to start threads.
- **Add Reactions** to react to messages.
- **Embed Links** so links and rich content in its messages display.

With **Read-only** access, Houston never uses the posting permissions. You can
untick permissions in Discord's dialog, or later change the bot's role in
**Server Settings > Roles**; agents then get a clear error for what the bot can
no longer do. To keep the bot out of a private channel, leave it out of that
channel's permissions: Houston only sees channels its role can view.

### Who can connect a server

Anyone with **Manage Server** can connect your server to their own Houston
account. Every such connection sees all the channels the bot's role can view,
including private channels another admin opened to the bot, and keeps working if
its creator later leaves the server or loses **Manage Server**. Keep private
channels closed to the bot unless every connection may read them. To cut off
every connection to your server at once, remove Houston from the server.

### Several servers

Each connection covers the one server you chose. Add another Discord connection
for each additional server. Editing a connection cannot move it to a different
server: Discord asks you to pick a server again, and choosing another one is
refused, so add a new connection instead.

### Changing the access level

Edit the connection and choose the other access level. The bot's permissions in
your server stay the same.

### Messages are missing or empty

If agents find no messages in a channel, check that the bot's role can view
that channel and has **Read Message History** there. Discord only shares the
text of other people's messages with apps it allows to read message content; if
messages come back without their text even though the bot can read the channel,
contact Houston support.

### Removing Houston from your server

Removing the connection in Houston deletes its stored authorization, but the
bot stays in your server, because other connections may use it. To remove it,
open **Server Settings > Integrations** in Discord, select Houston and choose
**Remove from server** (or kick the bot from the member list). Any connection to
that server then reports that Houston was removed; add it again from the
connection's settings to resume.
