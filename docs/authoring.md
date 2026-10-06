# Authoring a Houston connector

A connector release serves one service through one selected native protocol. The
manifest controls setup and credential injection. Its Luau entrypoints return
plain tables of public functions, which Houston executes on the server. Caller
scripts invoke those functions with JSON data; they never receive transport
handles, credentials, or connector source authority.

## Bundle

```
connectors/example/
  houston.json
  connector.lua
  lib/http.lua
  icon.svg
  tests/behavior.lua
```

`files` is a required nonempty array of entrypoints. Private imports use exact
canonical paths relative to the manifest, such as `require("lib/http.lua")`.
Every imported file belongs to the pinned release; imports cannot cross bundles.
Entrypoints return function maps, without metadata or implicit context arguments.
Duplicate export names fail publication. Initialization cannot make network calls.

```json
{
  "schema_version": 1,
  "name": "Example",
  "description": "Read Example items.",
  "files": ["connector.lua"],
  "auth": {
    "token": {
      "type": "manual",
      "label": "API token",
      "config": {"token": {"type": "secret", "label": "Token", "required": true}}
    }
  },
  "proxy": [{
    "protocol": "http",
    "origins": {
      "https://api.example.com": {
        "headers": {"Authorization": {"value": "Bearer {{auth.token.token}}"}},
        "allowlist": [{"methods": ["GET"], "paths": ["/items"]}]
      }
    }
  }]
}
```

```lua
local request = require("lib/http.lua")
return {
    listItems = function()
        return request.send({method = "GET", url = "https://api.example.com/items"})
    end,
}
```

The repository's canonical convenience helper is `helpers/http.lua`. Run
`go run ./tools/sync-helpers` after changing it; generated copies remain entirely
inside each standalone bundle. Helpers have no authority of their own. Only the
native invocation-bound `http.request` or `db.query` can transport requests.

## Settings and authentication

`publisher`, root `config`, and manual `auth.<key>.config` share the same Field
schema. Types are `string`, `boolean`, `integer`, `number`, and `secret`. A string
with `options` renders a choice. Optional `default`, numeric bounds, string length
bounds, `required`, and `order` drive validation and forms. The public JSON schema
is generated from the authoritative Go `manifest` package. Unknown fields,
duplicate keys, explicit null, and malformed references are errors.

Publisher settings belong to a registration. Root settings belong to a connection.
Manual inputs belong to that connection and selected method. Secrets in any of
these locations remain server-only. Only active nonsecret root settings appear in
the immutable Luau `config` table. `display: "masked"` on a normal string affects
presentation only; it is not secret storage.

Authentication methods are a map with stable keys, ordered by `order`, then key.
Manual methods declare their own inputs. OAuth methods declare endpoints and
reference publisher string `client_id` and secret `client_secret` fields. Enter
those values in the registration's declared publisher form. Use the exact callback
URL displayed for that registration in the provider's development app. OAuth
scopes are ordered groups of `{values: [...]}` with optional `if` predicates.

An omitted `auth` map permits root-secret injection without a synthetic method.
Fields activate through the bounded `if` operations `is`, `isDefined`, and `and`.
Dependencies precede presentation order. Missing required selectors are errors;
inactive saved values cannot satisfy references. Templates use explicit owners:
`publisher.name`, `config.name`, `auth.token.token`, or an OAuth method's
`auth.oauth.access_token`. Fallback `||` is available for values, not predicates.

Updating settings must distinguish omission (retain), reset (apply a declared
default), replacement, and explicit secret clearing. Saved secret values never
round-trip through forms. A method switch completes the new authentication before
it activates; failures never reuse another method's credentials.

## Transport and exports

`proxy` is a nonempty array of complete variants. Exactly one must match. HTTP
origins are literal HTTPS origins, without wildcards or interpolation. Independent
origin recipes inject object-shaped headers and optional object-shaped Basic
credentials. An allowlist entry may replace the whole header map or disable Basic.
Unlisted requests fail, and redirects are not followed automatically. A new
provider endpoint requires an explicitly reviewed literal origin in a new release.
Fastmail's documented session/API and download origins are covered by its bundle.

Database variants declare host, integer port, database, user, password and verified
TLS; ClickHouse also selects `https` or `native`. Credentials and targets cannot be
overridden by Luau query arguments. Database URLs are not accepted. Publisher
credentials may be sent only to literal or publisher-owned database targets.

`http.request({url, method, headers, body, src?, dest?})` returns a response with
`status`, `headers`, and `body`; file transfers use invocation-scoped session files.
`fs.read`, `fs.write`, `fs.stat`, and `fs.signedGetUrl` operate within that session.
`db.query({query, params?, max_rows?, read_only?})` uses the selected database.
Postgres parameters use `$1`; MySQL uses `?`; ClickHouse follows its native driver
parameter syntax. These are protocol primitives, not a portable SQL interface.

Initialize JSON arrays with `json.decode("[]")`, including arrays that may be
empty. A plain empty Luau table encodes as a JSON object. For example,
`local folders: {{id: string, name: string}} = json.decode("[]")` preserves the
array shape when an account has no folders. Behavioral fixtures must cover both
empty and populated results for array-valued interface operations.

Read-only configuration is ordinary public config. A bundle can omit writes:

```lua
local exports = {read = read}
if config.access == "read-write" then exports.write = write end
return exports
```

Export selection must be deterministic. Routes do not infer write permissions,
and arbitrary SQL text is not a domain interface. Existing caller access controls
and provider/database grants remain part of authorization.

## Typed domain contracts

The trusted [interface registry](../interfaces/registry.json) is generated from
`interfaces/registry.go` using `go run ./tools/interfaces`. It defines operation
argument/result types and domain semantics, which drive guards and help.

- `mail.folders@1`: `listMailFolders()` lists normalized, ID-sorted folder/label
  metadata. Gmail and Fastmail implement it.
- `files.metadata@1`: `statFile(id)` returns normalized file/folder metadata,
  including byte size when known. Drive and Dropbox implement it.

These deliberately scoped capabilities do not promise portability for provider
extras. An interface is advertised only if all its operations are present; none
means inactive and a partial implementation fails. Publication also runs provider
behavioral fixtures. Arbitrary signature strings are not interface definitions.

## Tests and publication

```sh
go test ./...
go run ./tools/validate
```

Set `HOUSTON_CLI` to a newly built Houston runner and put the pinned
`luau-analyze` on `PATH`. A fixture returns a table with `scenario`, optional
public `config` overrides, optional `configure`, and `run`. The scenario contains
synthetic `publisher`, root `config`, `auth_method`, and selected `auth_config`
inputs. Houston resolves them through the production manifest contract before
projecting only active nonsecret root values into the fixture VM. Include every
declared auth method, proxy alternative and intended enabled/disabled surface.
Each claimed interface must be fully enabled and every operation successfully
called in fixtures. The host records actual calls through immutable export
wrappers; publication validates their arguments and returned values against the
trusted interface schema. Merely exporting names or writing a no-op fixture is
insufficient. Initialization is also checked without fixture transport mocks.
`configure` supplies synthetic
native responses before the real bundle initializes; it is a test-only environment.
Test actual helpers and exports, not replacement helper implementations.

```lua
return {
    scenario = {publisher = {}, config = {}, auth_method = "", auth_config = {}},
    configure = function()
        http = {request = function(req)
            assert(req.url == "https://api.example.com/items")
            return {status = 200, body = json.encode({items = {{id = "one"}}})}
        end}
    end,
    run = function(exports)
        assert(exports.listItems().items[1].id == "one")
    end,
}
```

In Hub, register a repository, revision and manifest path. Registration assigns
identity; manifests do not contain an ID, repository, release or callback URL.
Several publishers may register the same source with isolated settings. A source
verification challenge is optional evidence of source control, not permission to
borrow credentials. Fresh catalogs are empty until explicitly registered. Local
source registration uses Houston's development-only source adapter and the same
validation/release pipeline; see the main repository's local-development guide.
