# Connect your Microsoft account

1. Choose the access level:
   - **Read-only** to let agents read your calendars without changing anything.
   - **Read and write** to also let agents create, change and cancel events and
     answer invitations. Outlook emails the people involved about these changes.
2. Select **Continue with Microsoft**, sign in with your Outlook.com, work or
   school account, and select **Accept** on the permissions Microsoft lists.

Many work and school organizations require an administrator to approve
calendar access for new apps. If Microsoft shows **Need admin approval**, send
the request or ask your administrator to approve Houston, then connect again.

Houston keeps your Microsoft authorization on its server; agent scripts never
see it. An Outlook Calendar connection only reaches your calendars, calendars
others share with you, and your colleagues' free/busy times, even if you also
connect Outlook or OneDrive.

## Advanced: changing access and troubleshooting

- To change the access level, edit the connection and connect with Microsoft
  again. Microsoft asks only for permissions you have not granted yet, and keeps
  earlier ones; Houston enforces the level you choose.
- To revoke every permission you granted Houston, remove Houston from
  [your Microsoft account's apps](https://account.live.com/consent/Manage) (personal
  accounts) or [My Apps](https://myapps.microsoft.com) (work or school accounts).
  This disconnects all your Microsoft connections in Houston. To stop using
  only Outlook Calendar, remove its connection in Houston.
- With Read and write access, agents can also change events in calendars
  other people share with you, where you have edit permission.
- Free/busy lookups for colleagues work only with work or school accounts.
