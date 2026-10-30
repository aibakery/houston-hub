# Add Docker Hub

The connector reads Docker Hub's public repositories, so you need no Docker
account, access token or developer app.

1. In Houston, add the Docker Hub connector and select **Add connector**. There
   are no settings to fill in.
2. Grant the appropriate members access to the connection.

You can then ask about public images, for example the latest tags of nginx, the
platforms and size of `python:3.13-slim`, or the most pulled repositories of an
organization.

## Advanced: troubleshooting

- **Private repositories, organizations and teams are not available**: Docker
  Hub accepts personal and organization access tokens only through a sign-in
  step that exchanges them for a short-lived session, and Houston connectors
  can't do that yet. Until they can, the connector reads public data only and
  takes no token, so a private repository looks as if it didn't exist.
- **A list stops after 100 repositories or 1,000 tags**: Docker Hub limits how
  far a list can go without signing in. Ask for repositories or tags whose name
  contains a word or version instead, such as tags with `alpine`.
- **An official image is not found**: Docker Official Images, such as `nginx` or
  `postgres`, belong to the `library` namespace on Docker Hub.
- **Requests are refused for a while**: Docker Hub allows each server about 180
  requests a minute, and every Houston user shares Houston's servers. Wait a
  minute and try again.
- See the [Docker Hub API documentation](https://docs.docker.com/reference/api/hub/latest/)
  for how the data is organized.
