# Houston Hub

[Explore the Hub](https://hub.ok-houston.com) · [Houston](https://ok-houston.com) · [Dashboard](https://ok-houston.com/dashboard)

Connect your agents to the tools you use. Houston Hub is the public home for Houston connectors—from Slack and Gmail to Postgres and Fastmail.

Each connector is a small, reviewable bundle: a `houston.json` manifest, a Lua module, and tests. The manifest describes setup and server permissions; the module defines what agents can do. Credentials stay on Houston.

Browse [`connectors/`](connectors/), copy a similar bundle, and make it your own. Both `.lua` and `.luau` work. New services usually need no changes to Houston itself.

```sh
go run ./tools/validate
houston test-connectors .
```

Read the [authoring guide](docs/authoring.md) for authentication choices, request policies, module exports, and examples. Submit a pull request when your connector is ready. After review and merge, Houston serves the new Git revision automatically—no version folders or client rebuilds needed.
