# Connect your Microsoft account

You need a work or school Microsoft account: Microsoft's Excel API does not
support personal accounts such as Outlook.com.

1. Choose the access level:
   - **Read-only** to let agents read your workbooks without changing anything.
   - **Read and write** to also let agents create workbooks and change cells,
     tables and worksheets.
2. Select **Continue with Microsoft**, sign in with your work or school
   account, and select **Accept** on the permissions Microsoft lists.

Microsoft's permission covers all your files, but Houston keeps your
authorization on its server, agent scripts never see it, and an Excel
connection only reads and changes Excel workbooks in your own OneDrive, even if
you also connect other Microsoft services. One exception: to create workbooks,
Read and write access can write a file by name in your OneDrive, as OneDrive's
Read and write access can. Creating a workbook never replaces an existing file,
but an agent's own script could replace a file whose name it knows.

## Advanced: changing access and troubleshooting

- To change the access level, edit the connection and connect with Microsoft
  again. Microsoft asks only for permissions you have not granted yet, and keeps
  earlier ones; Houston enforces the level you choose.
- To revoke every permission you granted Houston, remove Houston from
  [My Apps](https://myapps.microsoft.com). This disconnects all your Microsoft
  connections in Houston. To stop using only Excel, remove its connection in
  Houston.
- Work or school accounts can require an administrator's approval for new apps.
  If Microsoft shows **Need admin approval**, ask your administrator to approve
  Houston.
- If Microsoft says you can't sign in with a personal account, connect with a
  work or school account instead, and keep the workbooks in its OneDrive.
