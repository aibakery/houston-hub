# Connect your Google account

1. Choose the access level:
   - **Read-only** to let agents read without changing anything.
   - **Read and write** to also let agents deploy, run jobs, manage instances and
     change storage objects.
2. Select **Continue with Google**, choose your account, and approve the
   permissions Google lists. If Google shows a checkbox per permission, tick
   them all: Houston refuses a partial grant.

Agents can only do what your account may do in each project. For read-only use,
the **Viewer** role and the **Service Usage Consumer** role on a project are
enough, and searching logs needs both; narrower roles, such as **Logs Viewer**, cover a single area. Writes
need roles that allow them, such as **Cloud Run Developer** or **Compute
Instance Admin (v1)**. Ask a project owner to grant roles on the
[IAM page](https://console.cloud.google.com/iam-admin/iam).

> **Read and write** asks Google for full access to Google Cloud on your behalf.
> Houston's connector only offers the actions listed in its description, but use
> an account whose roles match what you want agents to do.

## Advanced: changing access and troubleshooting

### A Google Cloud API is disabled

If agents report that an API is disabled in a project, a project owner can turn
it on under [APIs & Services](https://console.cloud.google.com/apis/library),
or follow the link in the agent's error.

### Google Workspace organizations

- Workspace administrators can block third-party apps. If Google refuses the
  connection, ask your administrator to trust Houston under **Security** >
  **Access and data control** > **API controls** in the
  [Admin console](https://admin.google.com).
- An organization may require signing in to Google Cloud again after a set time
  (**Google Cloud session control**). When that time passes, the connection
  stops working: edit it and connect with Google again. Administrators can
  exempt trusted apps from session control.

### Changing access and revoking

- To change the access level, edit the connection and connect with Google again.
  Google then asks for the new set of permissions.
- To revoke access, remove the connection in Houston, or remove Houston from
  [your Google Account's third-party connections](https://myaccount.google.com/connections).
