# Connect your Microsoft account

1. Choose the access level:
   - **Read-only** to let agents read your contacts without changing anything.
   - **Read and write** to also let agents add, change and delete contacts and
     contact folders.
2. Select **Continue with Microsoft**, sign in with your Outlook.com, work or
   school account, and select **Accept** on the permissions Microsoft lists.

Many work and school organizations require an administrator to approve
**Read and write** access for new apps; **Read-only** usually needs no
approval. If Microsoft shows **Need admin approval**, send the request or ask
your administrator to approve Houston, then connect again.

Houston keeps your Microsoft authorization on its server; agent scripts never
see it. An Outlook Contacts connection only reaches your own contacts and
contact folders, even if you also connect other Microsoft services.

## Advanced: changing access and troubleshooting

- To change the access level, edit the connection and connect with Microsoft
  again. Microsoft asks only for permissions you have not granted yet, and keeps
  earlier ones; Houston enforces the level you choose.
- To revoke every permission you granted Houston, remove Houston from
  [your Microsoft account's apps](https://account.live.com/consent/Manage) (personal
  accounts) or [My Apps](https://myapps.microsoft.com) (work or school accounts).
  This disconnects all your Microsoft connections in Houston. To stop using
  only Outlook Contacts, remove its connection in Houston.
- Contacts in folders other people share with you, your organization's
  directory, public folders, archive mailboxes and on-premises Exchange
  mailboxes are out of reach.
