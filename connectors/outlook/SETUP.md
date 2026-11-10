# Connect your Microsoft account

1. Choose the access level:
   - **Read-only** to let agents read without changing anything.
   - **Read and draft** to also let agents prepare drafts, replies and forwards
     for you to review and send from Outlook. Agents can also update or delete
     existing drafts, but Houston refuses every send request on this level.
   - **Read and write** to also let agents send, reply, forward and organize mail.
2. Select **Continue with Microsoft**, sign in with your Outlook.com, work or
   school account, and select **Accept** on the permissions Microsoft lists.

Most work and school organizations require an administrator to approve mail
access for new apps. If Microsoft shows **Need admin approval**, send the
request or ask your administrator to approve Houston, then connect again.

Houston keeps your Microsoft authorization on its server; agent scripts never
see it. An Outlook connection only reaches your mail, even if you also
connect other Microsoft services.

## Advanced: changing access and troubleshooting

- To change the access level, edit the connection and connect with Microsoft
  again. Microsoft asks only for permissions you have not granted yet, and keeps
  earlier ones; Houston enforces the level you choose.
- To revoke every permission you granted Houston, remove Houston from
  [your Microsoft account's apps](https://account.live.com/consent/Manage) (personal
  accounts) or [My Apps](https://myapps.microsoft.com) (work or school accounts).
  This disconnects all your Microsoft connections in Houston. To stop using
  only Outlook, remove its connection in Houston.
- A work or school account without an Exchange Online mailbox connects, but
  reading mail then fails: Microsoft reports that the mailbox is not enabled for
  this access.
