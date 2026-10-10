# Houston Hub

This repository contains thirteen connector bundles, the authoritative manifest v1
contract and reviewed operation access metadata. Registrations in Houston define the live
catalog; repository files are not published automatically.

A bundle contains `houston.json`, declared Luau entrypoints, private helpers and
behavioral fixtures. Houston executes its exported operations on the server with
one privately bound native transport. Credentials never enter connector code.

Public CI runs the self-contained manifest contract tests, with no private
repository access or Houston runtime required:

```sh
go test ./manifest
```

The full suite runs in Houston's Dagger checks, where the runtime is built from
the same source as the application. To run it locally with that runtime:

```sh
go test ./...
go run ./tools/validate
```

Set `HOUSTON_CLI` to a freshly built Houston runner and put the pinned
`luau-analyze` on `PATH`; the Go validator runs every resolved behavior fixture
in the selected bundle. Fastmail and Notion are the supported connectors for
runtime validation; other provider bundles remain available for future migration.
From the Houston checkout, `go -C tools/runtime run . test-connectors` builds the
runner and invokes this validator. See the
[authoring guide](docs/authoring.md) and [provider bundles](connectors/). Register a copied bundle or an edited local
source through Hub; each registration owns its publisher settings independently.

For implementation ideas, see the optional [Luau practices](docs/luau-practices.md).
These are recommendations, not additional contribution requirements.

## Repository layout

- [connectors/](connectors/): provider manifests, Lua implementations, icons and tests.
- [docs/](docs/authoring.md): authoring instructions and [provider operation reference](docs/connectors/).
- [tools/](tools/): the public validator and its reusable typecheck/conformance packages.
- [manifest/](manifest/): shared manifest parser and generated schema used by Houston.

Use `go run ./tools/validate [bundle-directory]` for a selected bundle, or omit
the path to validate Fastmail and Notion. Use `go run ./tools/validate .` to explicitly
validate every bundle, including providers that have not yet migrated to the
current runtime. This command performs manifest validation, Luau type checking
and mocked behavior verification.
