---
name: houston-connector
description: Create or update Houston Hub connector bundles, including Luau operations, help, manifests, and behavior fixtures.
---

# Create a Houston connector

Work in the Hub checkout. Paths below are relative to its root, so they also
apply when this skill is installed separately.

Read `AUTHORING.md` for the bundle contract, native runtime examples, validation,
and publication workflow. Read `docs/luau-practices.md` for the shared coding
guidelines. Implement sequentially, keep operations and help together, reuse small
helpers and avoid registration indirection. The Hub accepts only Luau source and
fixtures; shared Go tooling belongs to the Houston repository.

## Establish the operation contract

Read the provider's official API and authentication documentation for the requested
operations. Identify permissions, pagination, limits, response shapes, and how
writes report success or partial failure. Use sibling connectors for relevant
provider or transport behavior, checking assumptions against the provider docs.
Keep changes scoped to the requested connector and behavior.

Create or update the bundle's `houston.json`, Luau entrypoints, provider icon,
short user-facing README and SETUP, and Luau behavioral fixtures. README explains
capabilities and access; SETUP contains only account connection steps, with rare
options under Advanced. Use headings, quotes and setup code blocks where useful.
Agents learn signatures and examples through `help()`, never these user documents. Keep credentials in
manifest injection rules and initialization and help free of network calls.
Expose only operations available under the configured access and permissions.

## Make each operation easy to review

Prefer the sequential layout in `connectors/postgres/connector.luau`: put an
operation's help record immediately before its direct `exports` function
definition, with descriptions and examples inline. Keep a conditional operation
and its help inside the same access condition. Prefer this readable layout even
when it takes more lines than maps of implementations or registration machinery.

Reuse shared transport handling, validation, and schemas. Follow the
tradeoffs in `docs/luau-practices.md`: keep provider details visible, types useful,
state small, and pagination and allocations bounded. PostgreSQL is a help/layout
example; use a connector with the appropriate transport for provider mechanics.

For structured help, describe arguments, optional values, return shapes, limits,
and mutation behavior accurately. Match positional bindings and schemas to the
actual signature, and provide realistic examples that fixtures can execute.
Use PostgreSQL's help records and fixtures as a working example with a runtime
that supports structured help; consult the
[runtime help contract](https://ok-houston.com/docs/connectors/SKILL.md)
for the full metadata format.

## Verify the real behavior

Exercise the real connector with mocked native requests and meaningful result
assertions. Choose cases relevant to the change: read-only access, bound arguments,
empty or null responses, pagination, provider errors, and confirmed or partial
writes. Prefer executing documented examples, as the PostgreSQL fixtures do.
Test observable behavior rather than source layout or helper names.

Run the validator from a Houston checkout with this Hub revision in `hub/`:

```sh
go -C tools/runtime run . test-connectors connectors/postgres
```

Follow `AUTHORING.md` under “Tests and publication” for the current Houston runtime
and Luau analyzer prerequisites. Report which checks ran and any blockers; do not
add source-spelling tests just to enforce these guidelines. Repository
changes do not publish a connector: use the separate publication workflow when
publication is requested.
