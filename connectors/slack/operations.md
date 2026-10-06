# Slack operations

Provider-specific exported operations retain the documented request and pagination semantics.

# Slack

Each instance is one user account in one authorized Slack workspace. Personal
connections are private to their owner. Shared connections are available to the
organization admins and granted members. Add a separate connection for each Slack
workspace. Tokens stay on Houston; posts are authored by the connected Slack user.
Use dot calls, channel IDs, user IDs, and timestamps as strings (never numbers).

Read functions:
- getProfile(): authenticated user_id, team_id, team, and user.
- listChannels(opts?): your channels and DMs via users.conversations. Options:
  types (comma-separated public_channel,private_channel,im,mpim), exclude_archived,
  limit, cursor. Returns channels and nextCursor.
- getChannel(channel): channel details.
- listMessages(channel, opts?): messages, has_more, nextCursor. Options: limit,
  cursor, oldest, latest, inclusive. Default limit 15.
- getThread(channel, ts, opts?): parent and replies, has_more, nextCursor; same
  options as listMessages. One page per call, default 15. Loop with cursor =
  result.nextCursor in the same run until absent. History can also use latest
  set to the last message ts if has_more is true without a cursor.
- searchMessages(query, opts?): matches, total, paging, nextPage. Slack search
  syntax: in:general, from:me, after:2026-01-01. Options: count, page, sort,
  sort_dir. Loop with page = result.nextPage until absent.
- listMentions(opts?): search results for mentions of your authenticated Slack
  user, including replies. Same search options plus query to narrow the search.
- listMembers(channel, opts?), listUsers(opts?): cursor pagination.
- getUser(user): profile. getPermalink(channel, ts): message link.
- getFile(id): attachment metadata. Message files arrays contain these IDs.
- downloadFile(id, path): stream a file into a session path; returns
  {path, url, bytes} with a Houston signed GET URL. Never inline attachment bytes.

Write functions (only present on read-write connections):
- postMessage(channel, text, opts?): send as yourself. Options include thread_ts,
  blocks, attachments (Slack message attachment objects), unfurl_links,
  unfurl_media, reply_broadcast, and client_msg_id. Returns ts and message.
- reply(channel, ts, text, opts?): send into a thread.
- updateMessage(channel, ts, text, opts?), deleteMessage(channel, ts): your messages.
- openConversation(users): user ID, comma-separated IDs, or an array of IDs;
  returns a DM/group channel to pass to postMessage.
- addReaction/removeReaction(channel, ts, name): emoji name without colons.
- uploadFile(path, opts?): stream a session file with Slack's external upload
  flow. Options: filename, title, alt_text, channel, thread_ts, text (initial
  comment). Set channel to share the file; omit to keep it private in Slack.
  Use fs.signedPutUrl to receive large files first. Returns files metadata.

Slack enforces the granted scopes and your workspace's permissions. Errors such
as missing_scope or not_in_channel propagate; HTTP 200 with ok=false is a failure.
Rate limits vary by app distribution, especially history/replies. A 429 means
retry later; no automatic retries or duplicate posts. A timeout during posting
can be ambiguous: check the channel before sending again. Search follows Slack's
own indexing and filters; it is not an unread-notifications API.

Example:
return { run = function()
    local slack
    for _, c in houston.connectors() do
        if c.type == "slack" then slack = c; break end
    end
    assert(slack, "Connect Slack first")
    return slack.listMentions({ count = 10 })
end }
