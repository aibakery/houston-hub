# Connect Discord

You need **Manage Server** permission. Houston installs its own bot; no app setup
is required.

1. Choose **Read-only** or **Read and write** in Houston.
2. Select **Continue with Discord**, sign in and choose the server.
3. Review permissions and select **Authorize**.

> Every connection to this server sees channels Houston's bot can view, including
> private channels. Connections keep working if their creator leaves. Only grant
> the bot access to channels every connected account may read.

## Advanced

Discord grants the same bot permissions at either access level; Houston blocks
writes on read-only connections. Adjust the bot's role/channel permissions to
restrict reading, posting, threads or reactions. Missing messages may mean the bot
lacks **View Channels** or **Read Message History**; contact Houston support if
message text is empty despite those permissions.

Each connection covers one server; add another for a different server. Changing
Houston's access level does not change the bot's Discord permissions.

Deleting a Houston connection leaves the shared bot installed. To stop all access,
remove Houston under **Server Settings → Integrations** or kick the bot.
