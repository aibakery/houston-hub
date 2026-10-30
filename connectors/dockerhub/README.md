---
description: Read public Docker Hub repositories and image tags, with their digests, platforms, sizes and push dates.
---

# Docker Hub

Let agents look up container images on Docker Hub: the Docker Official Images
such as nginx, Python or Postgres, and the public repositories of any user or
organization.

## Browse repositories

- List a user's or organization's public repositories, filter them by name and
  sort them by name, last push or pull count.
- Read a repository's description and overview, its star and pull counts,
  storage size, categories and when it was last updated.

## Check image tags

- List a repository's tags, most recently pushed first, or find the tags whose
  name contains a version or variant, such as `1.27` or `alpine`.
- Read a tag's digest, its images for each platform (such as linux/amd64 and
  linux/arm64) with their own digests and sizes, and when it was last pushed and
  pulled.

This is useful to find which version a tag points to, whether an image supports
your platform, how large it is or how recently it was updated.

The connector reads public data only, without a Docker account. It can't see
private repositories, organizations or teams, change descriptions, delete tags
or show Docker Scout vulnerability reports: Docker Hub only accepts access
tokens through a sign-in step that Houston doesn't support yet. Docker Hub
limits how often each server can ask, and every Houston user shares that limit.
This connector is not affiliated with or endorsed by Docker.

[Add Docker Hub](SETUP.md).
