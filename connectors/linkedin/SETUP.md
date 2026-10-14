# Connect your LinkedIn account

1. Choose the access level:
   - **Read-only** to let agents read your basic profile.
   - **Read and write** to also let agents publish and delete posts as you.
2. Select **Connect with LinkedIn**, sign in to LinkedIn and allow access.

Houston keeps your LinkedIn authorization on its server; agent scripts never see
it.

## Advanced: access, expiry and troubleshooting

### Reconnect every 60 days

LinkedIn access expires after 60 days and LinkedIn does not let ordinary apps
renew it automatically. When agents report that LinkedIn access expired, edit the
connection and connect with LinkedIn again.

### Changing the access level

Switching between **Read-only** and **Read and write** asks LinkedIn for
different permissions, so edit the connection and connect with LinkedIn again.
LinkedIn then replaces the previous authorization.

### Revoking access

To stop Houston posting as you, remove the connection in Houston and revoke
Houston in LinkedIn's [permitted services](https://www.linkedin.com/psettings/permitted-services).
