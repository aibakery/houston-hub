# Houston Hub

This repository contains twelve connector bundles, the authoritative manifest v1
contract and trusted domain interfaces. Registrations in Houston define the live
catalog; repository files are not published automatically.

A bundle contains `houston.json`, declared Luau entrypoints, private helpers and
behavioral fixtures. Houston executes its exported operations on the server with
one privately bound native transport. Credentials never enter connector code.

```sh
go test ./...
go run ./tools/validate
```

Set `HOUSTON_CLI` to a freshly built Houston runner and put the pinned
`luau-analyze` on `PATH`; the Go validator runs every resolved behavior fixture.
From the Houston checkout, `go -C tools/runtime run . test-connectors` builds the
runner and invokes this validator. See the
[authoring guide](docs/authoring.md), [typed interface registry](interfaces/registry.json)
and [provider bundles](connectors/). Register a copied bundle or an edited local
source through Hub; each registration owns its publisher settings independently.
