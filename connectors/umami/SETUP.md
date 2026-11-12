# Connect Umami

1. In Umami, open your profile menu, then **Settings → API keys**, and create a
   key. Copy it when shown.
2. Add the Umami connection in Houston. Keep **API host** as `api.umami.is` and
   **Deployment** as **Cloud**, or choose US/EU explicitly.
3. Paste the key into **API key or self-hosted bearer token**.
4. Keep read-only access, enable all reads and writes, or choose **Custom** and
   set access independently for each area you want to use. Save the connection.

Umami keys have the account's permissions. Houston's access selections restrict
this connection; they do not reduce the key's permissions elsewhere. Account and
administration writes include credential and security settings, so enable them
only when needed.

## Self-hosted installations

Choose **Self-hosted**, and replace **API host** with the installation's public
HTTPS hostname, optionally including its port. Do not include `https://` or a
path. The API must be reachable at `/api`; private-network addresses and custom
base-path installations are not supported by this connector's routes.

Use an API key from Umami 3.4.1, or paste an existing bearer token obtained through
Umami's login flow. Complete any two-factor sign-in in Umami first. Houston never
asks scripts for the connection's password or signs in on their behalf. If a
temporary bearer token expires, edit the connection and replace it.

Cloud does not expose user-management routes or password changes. Other features
depend on your Umami role, deployment, database and plan. A 401 usually means the
credential needs replacing; a 403 may mean the account lacks permission. Cloud
limits each key to 50 calls per 15 seconds.
