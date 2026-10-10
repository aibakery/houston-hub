# Authoring a Houston connector

A connector release serves one service through one selected native protocol. The
manifest controls setup and credential injection. Its Luau entrypoints return
plain tables of public functions, which Houston executes on the server. Caller
scripts invoke those functions with JSON data; they never receive transport
handles, credentials, or connector source authority.

The optional [Luau practices](luau-practices.md) suggest ways to keep interfaces,
state and allocations simple. They do not add publication or style requirements.

## Bundle

```
connectors/example/
  houston.json
  README.md
  SETUP.md
  connector.lua
  icon.svg
  tests/behavior.lua
```

`files` is a required nonempty array of entrypoints. Private imports use exact
canonical paths relative to the manifest, such as `require("lib/pagination.lua")`.
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
  "proxy": [
    {
      "action": {
        "headers": {
          "set": {
            "Authorization": "Bearer {{auth.token.token}}"
          }
        }
      },
      "match": {
        "host": [
          "api.example.com"
        ],
        "method": [
          "GET"
        ],
        "path": [
          "/items"
        ],
        "protocol": "http"
      }
    }
  ]
}
```

```lua
return {
    listItems = function()
        local response = await(http.request({method = "GET", url = "https://api.example.com/items"}))
        if response.statusCode ~= 200 then
            response.body:close()
            error("Example service request failed")
        end
        return json.decode(await(response.body:readAll()))
    end,
}
```

`http` is provided natively by the sandbox for HTTP connections. Call
`http.request` directly and handle the provider's status and response format in
the connector. No HTTP module import or generated helper copy is needed. The
request completes within the invocation, including uploads and downloads.

## Execution and waiting

Each exported operation runs in a fresh connector VM and returns completed plain
data. Connectors and caller scripts share `http.request`, `fs`, `compression`,
`await`, and `awaitAll`. A request starts immediately and its operation settles
when final headers and a body Reader are available. `await` retrieves the result;
it does not start or rerun work. A local session cache lasts only for that
invocation. No background work continues through another invocation.

Use sequential bounded batches as the baseline. The current runner limits each
invocation to 256 native calls, including file operations, 64 MiB of Lua memory,
and 8 MiB per JSON transport frame. Server deadlines and transport limits also
apply. Paging and smaller requested fields/body values avoid exhausting these
budgets; batching alone does not bound a result that accumulates every page.
These are execution limits, not limits on total process memory or attachment
file size. Upload with `body = fs.open(path, "r")`; download by writing the
response Reader to `fs.open(path, "w")` and awaiting the file's final close.
Reader pipelines use bounded native buffers. `readAll(maxBytes?)` explicitly
allocates a string, defaults to 8 MiB, and fails and closes its source on overflow.

Neither an error nor a timeout rolls back changes the provider has already
accepted. Do not automatically replay partial batches or ambiguous writes;
document how callers can inspect the outcome. Use `awaitAll` for bounded groups
of independent operations. Results are packed in input order with an `n` field,
including nil results; iterate from 1 to `results.n`. An ordinary rejection does
not cancel siblings. Both await helpers accept an optional timeout in milliseconds;
expiry cancels unfinished work before raising a structured `timeout` error.
Cancellation is not rollback. Completed results remain unchanged.

HTTP `timeoutMs` ends when final headers are available. Body reads can have their
own timed awaits. Responses use `statusCode` and a canonical header map whose
values are arrays of strings, including single values. Response names are
lowercase. Non-2xx statuses are ordinary responses. Consume or close every body.
The runtime supports gzip `Content-Encoding`, including nested gzip layers,
and advertises only gzip. Unsupported or malformed coding chains fail explicitly.
Decoding is lazy; received headers still describe the encoded response.
File media types and filenames never trigger decoding.

Files open asynchronously: `local fd = fs.open(path, "w")` returns a File that
accepts ordered work before opening finishes, and `await(fd) == fd`. Queue writes
and seek operations, then `await(fd:close())` to finish work and release the file.
Repeated close returns the same operation. Wrong-mode, closed-handle, argument,
and admission errors raise at the call; later I/O errors raise at await or final
close. Catch the completion boundary, not only the scheduling call. Files remain
open at EOF and support `seek(offset, "start" | "current" | "end")`.

An unfinished file operation's cancellation stops its queue. Close still releases
the handle and reports its first failure; writes may have partially changed the
destination. Discarding a method operation does not discard accepted queue work.
Keep the File alive until closing or transferring it to a consumer. GC cleanup
is abortive; explicit close is graceful. Invocation exit releases all resources
and rejects unobserved asynchronous failures or unfinished accepted work.

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

The immutable `auth` table contains the selected method key (`auth.method`) and,
when known, `auth.scopes`: granted OAuth scopes intersected with the selected
method's release-declared scope vocabulary. Undeclared upstream values and
credentials never enter this table. Nil scopes mean unknown (including manual
API tokens); an empty list means none of the declared scopes were granted.
Derive exports directly from `config` and these facts, without a second export
list. Do not infer manual token permissions from the token or probe operations
during initialization. Unknown upstream restrictions must produce clear errors
when an operation is invoked. Publication fixtures can set synthetic
`scenario.granted_scopes` to test known OAuth restrictions.

Houston restricts effective config using current caller grants; Lua selects the
exports from that config. Discovery is recomputed from the
current connection release, settings and authentication facts on each request;
existing client instances must be rediscovered to refresh their function list.
Invocation still checks current configuration and grants before dispatch.
Document signatures, defaults, results and mutation behavior in the connector's
Lua `help()` function, exposed as `instance.help()`. Teach callers to read help, never
to learn signatures by issuing live send/delete probes.

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

`proxy` is a nonempty ordered array of rules containing `match`, `action`, and an
optional `if` predicate. Within `proxy`, conditions belong only on rules, never
inside `match` or `action`. Enabled rules must share one protocol. For HTTP, the
first enabled rule matching the original request wins; only its action runs.
Rules never merge, rematch after changes, or fall through after errors.

```json
"proxy": [
  {
    "match": {
      "protocol": "http",
      "host": ["api.example.com", "*.api.example.com"],
      "method": ["GET"],
      "path": ["/v1/records/*"],
      "header": {"Accept": "application/json", "X-Request-ID": true}
    },
    "action": {
      "rewrite": {"strip_prefix": "/v1"},
      "headers": {
        "remove": ["SomeOtherHeader"],
        "set": {"Authorization": "Bearer {{auth.token.token}}"}
      }
    }
  }
]
```

HTTP requires `match.protocol: "http"` and a nonempty `host` array. Hosts have no
scheme or path; transport is HTTPS. One leading `*.` matches subdomains at any
depth, excluding the base hostname. Ports must match, with implicit and explicit
443 equivalent. Other wildcard positions and wildcard IPs are invalid. First-rule
priority also applies when an exact host and a wildcard both match.

Optional `method` and `path` arrays accept any listed value; different filter
fields combine with AND. Omission leaves that filter unrestricted; empty arrays
are invalid. Paths support exact paths, whole-segment `{id}` placeholders, and a
terminal `/*` subtree wildcard. Keep separate rules when different methods allow
different path sets: combining method/path arrays permits their Cartesian product.
All `header` entries must match. Header names are case-insensitive; string values
match exactly and `true` means present, including an empty value. Filters are
literal and inspect caller headers before action changes.

`action.headers.remove` runs before `set`. A set replaces existing values; a name
may appear in both collections. Set values are string templates only; objects
and nested conditions are invalid. For conditional injection, put a complete
conditional rule before a fallback rule. A false predicate skips the whole rule.
Only the selected action modifies headers; caller values otherwise remain intact.
`action.basic_auth` supplies native Basic credentials; it cannot be combined with
an `Authorization` set. `action: {}` intentionally passes a matching request
through. Signed-upload rules can explicitly remove `Authorization`.

Rule predicates may test selected-method markers and nonsecret settings. They
may also use `isDefined` for stored root, publisher, or selected manual-auth
secrets. Required credentials are validated first; absence cannot silently select
a fallback. Secret equality and managed OAuth token references are forbidden in
rule predicates, so token refresh cannot change the enabled rule set. OAuth
account headers are separate lifecycle declarations and retain their original
`{value, if?}` objects.

`rewrite.strip_prefix` strips a literal absolute nonroot prefix at a path boundary.
`/v1` maps `/v1/records` to `/records` and `/v1` to `/`; it does not match `/v10`.
The query and authority stay unchanged. A prefix mismatch fails the selected rule.
Trailing slashes, templates, wildcard/placeholder syntax, percent escapes, dot
segments, and repeated slashes are invalid prefixes.

Unmatched requests fail before transport, and redirects are not followed
automatically. A new provider endpoint must match a host filter in the pinned
release. Origin-denial errors report the origin without its path or query.
Fastmail shares API actions across `api.fastmail.com`, `*.api.fastmail.com`, and
`jmap.fastmail.com`. Separate download rules allow `fastmailusercontent.com` and
its subdomains, as documented in Fastmail's
[security documentation](https://www.fastmail.help/hc/en-us/articles/1500000280221-How-Fastmail-provides-a-secure-service).

Database rules contain only the protocol in `match` and native settings in
`action.connection`: host, integer port, database, user, password, and verified
TLS; ClickHouse also selects `https` or `native`. The first enabled database rule
wins. Credentials and targets cannot be overridden by Luau query arguments.
Database URLs are not accepted. Publisher credentials may be sent only to literal
or publisher-owned database targets.

`http.request({url, method, headers?, body?, timeoutMs?})` returns an operation
whose result has `statusCode`, `headers`, and a body Reader. All headers use
`{[string]: {string}}`; plain strings are invalid. `body` accepts bytes or a Reader.
`fs.open`, `stat`, `exists`, `list`, `grep`, `signedGetUrl`, and `signedPutUrl`
operate on invocation-scoped session files and return operations. `list` returns
all sorted child names or a limit error; `grep` returns `{matches, truncated}`.
`db.query({query, params?, max_rows?, read_only?})` uses the selected database.
Postgres parameters use `$1`; MySQL uses `?`; ClickHouse follows its native driver
parameter syntax. These are protocol primitives, not a portable SQL interface.

Initialize JSON arrays with `json.decode("[]")`, including arrays that may be
empty. A plain empty Luau table encodes as a JSON object. For example,
`local folders: {{id: string, name: string}} = json.decode("[]")` preserves the
array shape when an account has no folders. Behavioral fixtures must cover both
empty and populated results for array-valued operations.

Read-only configuration is ordinary public config. A bundle can omit writes:

```lua
local exports = {read = read}
if config.access == "read-write" then exports.write = write end
return exports
```

Export selection must be deterministic. Routes do not infer write permissions,
and arbitrary SQL text is not a domain interface. Existing caller access controls
and provider/database grants remain part of authorization.

## Configured exports, help, and provider validation

The connector Lua is the sole authority for configured functions and their help.
Return only functions enabled by the effective public configuration. Houston
clamps `config.access` to `read-only` for callers without a current write grant,
then uses the same configured Lua for discovery and execution. Native dispatch
rechecks current connection access and the effective configuration before each
transport request. Do not infer permission from function names or HTTP verbs.
Provider and database grants remain authoritative.

Export a pure `help()` function returning a nonempty string for precisely those
configured functions. Build the text from the same export table, including their
arguments, return shapes, pagination, and meaningful provider caveats. Houston
evaluates help with native transports disabled and excludes it from the callable
operation list. Help must be deterministic and must never probe credentials or
call a provider. Keep README documentation for humans; agent help comes from Lua.
There is no operation classification sidecar or exported metadata registry.

Provider functions validate their arguments and upstream responses. Keep plain-data
boundaries, nonempty IDs, finite safe integer sizes, explicit empty arrays, unique
folder IDs, provider errors and deterministic sorting covered by fixtures.
General Luau typechecking and native transport restrictions still apply.
Standardized cross-provider interfaces are deferred until actual portability needs
justify them. Connectors do not declare `implements`.

## Documentation and recommended manifest layout

Official examples should order root fields as `schema_version`, `name`,
`verification_key`, `files`, `icon`, `config`, `auth`, optional `publisher`, then
`proxy`. Omit unused optional sections. This is a readability convention; every
legal JSON property order validates. Formatting should preserve the source order.
Use adjacent `README.md` (optionally with `description` frontmatter for a card
summary) for a short, appealing overview of what people can do with the connector.
Describe useful capabilities and access choices in plain language. Put account
setup instructions in `SETUP.md`; keep function signatures, return shapes,
pagination rules, and agent examples in Lua `help()`. The Hub renders the README
as the public description, not as agent runtime documentation. Inline `description` and
`setup` remain supported fallbacks, but need not duplicate those files.

## Tests and publication

```sh
go test ./...
go run ./tools/validate connectors/fastmail
```

Replace `connectors/fastmail` with the bundle you are authoring. The no-argument
validator currently selects Fastmail; other providers will enter routine runtime
validation as they are migrated. An explicit catalog directory validates all its
bundles.

Set `HOUSTON_CLI` to a newly built Houston runner and put the pinned
`luau-analyze` on `PATH`. A fixture returns a table with `scenario`, optional
public `config` overrides, optional `configure`, and `run`. The scenario contains
synthetic `publisher`, root `config`, `auth_method`, and selected `auth_config`
inputs. Houston resolves them through the production manifest contract before
projecting only active nonsecret root values into the fixture VM. Include every
declared auth method, enabled proxy rule, and intended enabled/disabled surface.
Eligibility coverage does not establish which rule wins; matcher tests separately
cover rule order, request filters, and action behavior.
Fixtures assert actual provider arguments, responses and behavior. Publication
checks deterministic configured exports and requires each to have reviewed access
metadata. Initialization is also checked without fixture transport mocks.
`configure` supplies synthetic
native responses before the real bundle initializes; it is a test-only environment.
Test actual helpers and exports, not replacement helper implementations.
`fixture.operation(value)` and `fixture.reader(bytes)` construct real native
completed operations and Readers for synthetic provider responses;
`fixture.files()` provides isolated file storage with the production File API.
These helpers exist only in publication fixtures. Keep `await` and the stream
methods native so fixtures exercise the same completion and ownership boundaries.

```lua
return {
    scenario = {publisher = {}, config = {}, auth_method = "", auth_config = {}},
    configure = function()
        http = {request = function(req)
            assert(req.url == "https://api.example.com/items")
            return fixture.operation({statusCode = 200, headers = {},
                body = fixture.reader(json.encode({items = {{id = "one"}}}))})
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

`config.access` is a reserved public field. When declared it must be an
unconditional string field accepting `read-only`; defaults and options use only
`read-only` and `read-write`. An optional field without an explicit default
defaults to `read-only` before conditional fields, OAuth scopes, and proxies are
resolved. Required fields still require a value, and explicit null inputs are
invalid. When undeclared, Houston supplies `read-only`.
The publication type checker exposes this reserved field even if the manifest
does not declare a configurable Access setting.
