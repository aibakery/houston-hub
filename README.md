# Houston Hub

[Explore the Hub](https://hub.ok-houston.com) · [Houston](https://ok-houston.com) · [Dashboard](https://ok-houston.com/dashboard)

Connect your agents to the tools you use. This repository contains example connectors—from Gmail and Slack to Postgres and Fastmail.

A connector is a `houston.json` manifest and a Lua module, with an optional icon and tests. The manifest defines setup and server permissions; the module defines what agents can do. Credentials stay on Houston.

Copy a bundle from [`connectors/`](connectors/) into your own GitHub repository. In the dashboard’s **Connector Catalog**, provide the repository, branch and optional path. Houston validates it and publishes it immediately. Secrets and ownership verification are optional.

```sh
go run ./tools/validate
houston test-connectors .
```

See the [authoring guide](docs/authoring.md) for authentication choices, module exports and examples. Pull requests improve these examples; dashboard registrations determine what appears in the live Hub.
