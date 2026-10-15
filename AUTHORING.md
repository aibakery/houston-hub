# Create and publish a Houston connector

This guide is for connector authors and publishers. Connector folders contain
the bundle and its account-user documentation. Keep publisher setup, registration,
deployment requirements and development instructions here, outside those folders.

Start with the [Fastmail](connectors/fastmail/connector.lua) and
[Notion](connectors/notion/connector.lua) implementations. Fastmail demonstrates
provider-specific helpers and typed records; Notion demonstrates a broad REST
surface sharing a small request layer.

## Workflow

1. Read the provider's official API and authentication documentation. List the
   operations, required permissions, pagination and file-transfer behavior.
2. Create a bundle with a manifest, pure-initializing Lua entrypoints, official
   provider icon, account-user README and SETUP, and behavior fixtures.
3. Implement operations using the runtime examples below. Keep credentials in
   manifest injection rules, and derive both exports and help from effective access.
4. Validate the real bundle with the Go validator and current Houston runtime.
5. Commit and push the source, then register its repository, revision and manifest
   path in Houston's Hub. Connection admins configure account credentials when adding a connection.
6. Connect a test account using the same flow account users see. Check discovery,
   read-only behavior, paging and a provider-confirmed write on disposable data.

Use [runtime examples](#runtime-examples), [Luau practices](docs/luau-practices.md),
[validation](#tests-and-publication), and [publication](#publish-a-hub-publication)
as the detailed references for these steps.

A connector release serves one service through one selected native protocol. The
manifest controls setup and credential injection. Its Luau entrypoints return
plain tables of public functions, which Houston executes on the server. Caller
scripts invoke those functions with JSON data; they never receive transport
handles, credentials, or connector source authority.

The optional [Luau practices](docs/luau-practices.md) suggest ways to keep interfaces,
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

Set the optional root `stateless` boolean to `true` for service credentials that
access public/service data without linking a user's private account (for example,
X public browsing or Exa search). It defaults to `false`. Houston uses this
metadata to show a **Houston billing — Coming soon** banner during
connection setup. It does not supply credentials, change authentication, or charge
credits. Do not mark mailboxes, private workspaces, or databases as stateless.

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
`url`, `await`, and `awaitAll`. A request starts immediately and its operation settles
when final headers and a body Reader are available. `await` retrieves the result;
it does not start or rerun work. A local session cache lasts only for that
invocation. No background work continues through another invocation.

`await(operation, timeoutMs?)` requires an Operation or File. Connector calls
already return completed values: use `connector.getItem(...)` directly, without
`await`. The runtime rejects plain values with `invalid_argument` and explains
how to correct the call. Make this distinction explicit in the connector's
`help()` examples.

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
HTTP, multipart and compression Readers also offer `readPrefix(maxBytes)`: it returns
at most `maxBytes` bytes and closes the Reader. Longer bodies and source errors end
the prefix; it fails only when the Reader is closed, cancelled or already in use.
Use it for bounded error snippets. Files have no `readPrefix`:
`await(fd:read(maxBytes))` returns one `{done, data}` chunk of at most `maxBytes`
bytes.

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

Publisher settings belong to a Hub publication. Root settings belong to a connection.
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
reference a string `client_id` and secret `client_secret` field with one owner.
Connection-owned clients use `config.client_id` and `config.client_secret`: the
connection admin enters them in the connection form and registers its displayed
callback in the provider application, so each connection has a distinct callback.
Publisher-owned clients use `publisher.client_id` and `publisher.client_secret`:
the publisher registers one application whose redirect URI serves every connection
of the publication, and connection admins only authorize their account. OAuth
scopes are ordered groups of `{values: [...]}` with optional `if` predicates.
OAuth exchanges and refreshes default to form-encoded bodies. Providers such as
Notion can select `token_encoding: "json"` and supply literal `token_headers`
such as `Notion-Version`. These headers cannot replace authentication or
transport framing headers. Credentials still stay outside Luau.

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

For self-hosted services, a host can be one whole-value reference to a required,
unconditional string setting, such as `{{config.store_host}}` in WooCommerce.
Houston renders it when resolving each connection; the result must be one exact
origin, so wildcards, schemes and paths in the setting are rejected. Lua builds its
URLs from the same `config` value. Publisher secrets, including OAuth tokens obtained
with a publisher-owned client, cannot be sent to a host a connection controls.
Houston's egress still refuses private, loopback and link-local addresses.

Optional `method` and `path` arrays accept any listed value; different filter
fields combine with AND. Omission leaves that filter unrestricted; empty arrays
are invalid. Paths support exact paths, whole-segment `{id}` placeholders, and a
terminal `/*` subtree wildcard. Keep separate rules when different methods allow
different path sets: combining method/path arrays permits their Cartesian product.
All `header` entries must match. Header names are case-insensitive; string values
match exactly and `true` means present, including an empty value. Filters are
literal and inspect caller headers before action changes.

An API with opaque IDs can explicitly declare `opaque_path_parameters: ["id"]`
on a path such as `/records/{id}`. That parameter may contain encoded slash,
backslash, or percent bytes. For signed file keys, `["*"]` applies to an explicit
terminal wildcard, such as `/trusted-bucket/*`. Keep this on narrowly scoped
rules: every name must appear in each path, rewriting is forbidden, and literal
prefixes and other parameters remain strict. Matching preserves the original
escaped URL; traversal and control bytes are rejected through up to 16 decoding
passes. Other rules keep the default rejection of encoded separators and percent.

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
TLS. The protocols are `postgres`, `mysql`, `clickhouse` (its HTTPS interface)
and `redis`, whose database is a numeric index. The first
enabled database rule wins. Credentials and targets cannot be overridden by Luau
query arguments. Database URLs are not accepted. Publisher credentials may be
sent only to literal or publisher-owned database targets. An `imap` rule has the
same shape without a database: host, port (default 993), user, password and
verified TLS. IMAP connects with implicit TLS; STARTTLS is not supported.

`http.request({url, method, headers?, body?, timeoutMs?})` returns an operation
whose result has `statusCode`, `headers`, and a body Reader. All headers use
`{[string]: {string}}`; plain strings are invalid. `body` accepts bytes or a Reader.
`http.multipart({{name, body, filename?, contentType?}, ...})` returns a streaming
Reader and its `multipart/form-data` Content-Type (including a random boundary).
Set that Content-Type header on the request and pass the Reader as its body.
Part bodies accept strings, Readers, or readable Files. The helper takes ownership
of every Reader/File; closing or consuming the multipart Reader closes its sources.
Validation errors leave sources usable. Parts must form a nonempty dense array
of at most 128 entries, with at most 64 KiB of headers and 8 MiB of string bodies
in total. File contents stream without a size limit or temporary staging file.
`fs.open`, `stat`, `exists`, `list`, `grep`, `signedGetUrl`, and `signedPutUrl`
operate on invocation-scoped session files and return operations. `list` returns
all sorted child names or a limit error; `grep` returns `{matches, truncated}`.
SQL protocols provide `db.query({sql, params?, maxRows?, readOnly?})`, an
operation for one statement on its own connection. Postgres parameters use `$1`
and MySQL `?`, with `params` as an array; ClickHouse binds named placeholders
such as `{day:Date}` on the server, with `params` as a map like `{day = ...}`.
Parameters are strings, numbers, booleans or JSON null. Statements are read-only
unless `readOnly = false`, which needs write access. Read-only mode is the
database's own: a Postgres read-only transaction, a MySQL read-only session
that accepts only reading statements, or ClickHouse `readonly=1`. The result is
`{columns, rows, truncated, affectedRows?, lastInsertId?}`: rows are objects
keyed by column, NULL columns are absent, and `truncated` reports that `maxRows`
(default 1,000, at most 10,000) or the 4 MiB result budget stopped reading.
Postgres, MySQL and Redis return binary values, and text that is not valid
UTF-8, as `\x`-prefixed hex; ClickHouse queries select `hex(column)` instead.
Redis provides `db.command({args, readOnly?})` for one command, such as
`{"HGET", key, field}`; a read-only command must carry Redis's `readonly` flag,
and a missing value is nil. Database errors raise `database_error` with the
server's message. These are protocol primitives, not a portable SQL interface.
IMAP provides `imap.command({command, ...})`, an operation for one mail command
on its own connection. Houston logs in, decodes MIME and owns the message IDs;
the [IMAP connector](connectors/imap/connector.lua) documents each command and its
options. Fields are strings, numbers, booleans or arrays of them, and unknown
options are rejected. `store`, `move` and `create` change the mailbox and need
write access. IMAP errors raise `imap_error` with the reason or server's message.

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
Describe useful capabilities, access choices, limits, and costs in plain language.
The public description must not mention Lua/Luau, `help()`, callable function names,
request or response fields, pagination parameters, or code examples. This applies
to the README body, its `description` frontmatter, and the manifest's inline
`description`. Put all programming usage documentation in the connector's Lua
`help()` function; moving it there must preserve useful examples and caveats.

Put account setup instructions in `SETUP.md`: choosing an available authentication method,
obtaining an account token when needed, granting provider permissions, and adding
the account in Houston. State prerequisites explicitly, including whether a
provider developer app is required and whether users can select an existing app
or must create one. Verify credential labels against the provider's current
console and link its official instructions; do not assume an old tab name still
exists. Both files address people using an already registered
connector. Do not put repository publication, publisher settings, builds or
deployment instructions in any connector folder. The Hub renders the README as
the public description. Inline `description` and `setup` remain supported
fallbacks, but need not duplicate those files.

Keep the common setup steps first. A heading named `Advanced` (or starting with
`Advanced ` or `Advanced:`) becomes a collapsed expandable section in Houston,
ending at the next heading of the same or a higher level. Use subheadings for
optional configuration and troubleshooting inside it. Markdown formatting,
links, and bundled images still work; raw HTML stays disabled.

OAuth connectors show a reserved callback URL as soon as account setup opens,
before client credentials are entered. Put copying that URL into the provider's
app settings before entering the client ID and secret in your instructions.
Unfinished reservations expire after 24 hours or are discarded on cancellation.
Completed connections keep their callback URL when reauthorized.

## Tests and publication

```sh
go test ./...
go run ./tools/validate connectors/fastmail
```

Replace `connectors/fastmail` with the bundle you are authoring. The no-argument
validator selects the bundles migrated to the current runtime: Cal.com, Calendly, Dropbox, Fastmail, the Google connectors,
IMAP, LinkedIn, Mercury, Notion, Resend, WooCommerce, X
and the database connectors. Other providers will join as they are migrated. An explicit catalog directory validates all its
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
checks deterministic configured exports and help, and requires fixture scenarios
covering each authentication method and enabled proxy rule. Access is determined
by the configured Lua exports; there is no operation-access metadata sidecar.
Initialization is also checked without fixture transport mocks.
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

## Runtime examples

These snippets run inside connector functions. Replace the illustrative URLs and
provider fields with the service's actual API and declare their routes in the
manifest. Initialization and `help()` must stay free of I/O. Use small local
helpers for repeated protocol behavior; keep public operations and provider
semantics visible instead of building a generic SDK framework.

### JSON requests, errors and pagination

```lua
local function responseJSON(response: HttpResponse, operation: string): any
    if response.statusCode < 200 or response.statusCode >= 300 then
        local snippet = await(response.body:readPrefix(512))
        return houston.fail({
            operation = operation,
            layer = "upstream",
            upstream_status = response.statusCode,
            retryable = response.statusCode == 429 or response.statusCode >= 500,
            message = if snippet == "" then "Provider request failed" else snippet,
        })
    end
    return json.decode(await(response.body:readAll()))
end

local function getItem(id: string, opts: {fields: string?}?)
    local query = if opts and opts.fields then "?fields=" .. url.encode(opts.fields) else ""
    local response = await(http.request({
        method = "GET",
        url = "https://api.example.com/items/" .. url.segment(id, "id") .. query,
    }))
    return responseJSON(response, "getItem")
end

local function listItems(opts: {cursor: string?}?)
    local response = await(http.request({
        method = "POST",
        url = "https://api.example.com/items/query",
        headers = {["Content-Type"] = {"application/json"}},
        body = json.encode({cursor = if opts then opts.cursor else nil, limit = 50}),
    }))
    local page = responseJSON(response, "listItems")
    assert(type(page) == "table" and type(page.items) == "table",
        "Provider returned an invalid item page")
    return page -- Preserve the provider's continuation cursor; fetch one page.
end
```

`url.encode(value)` percent-encodes every byte outside RFC 3986's unreserved
characters; use it for query names and values. Numbers and booleans render as
`tostring` does. `url.segment(value, name?)` encodes
one path segment and raises `invalid_argument` for an empty value, a dot-only value
such as `..`, `/`, `\`, `%`, control characters or invalid UTF-8, naming `name`
but never echoing the value. Pass every caller-supplied path ID through it, or check
it against a strict format such as `^[%w_%-]+$` or a numeric ID, so an ID cannot add
path or dot segments. To keep a connector's own error text, wrap it:
`local ok, segment = pcall(url.segment, id)`.
Opaque IDs that may contain separators, such as Notion property IDs, use
`url.encode` and an `opaque_path_parameters` proxy rule instead.

Production helpers should also validate provider-specific error envelopes and
mutation confirmations, and catch malformed JSON where a structured error helps.
Keep error snippets bounded with `readPrefix` and avoid including secrets or signed
URLs. Classifying an error as retryable does not retry it: callers must verify
ambiguous writes before repeating them. Do not automatically collect every page
into memory.

JSON null is a truthy sentinel; a plain empty table is an object. Preserve the
provider's distinction between omission, explicit null and an empty array:

```lua
local patch = {cover = json.decode("null"), tags = json.decode("[]")}
local encoded = json.encode(patch) -- {"cover":null,"tags":[]}, key order may vary
```

### Stream downloads to session files

```lua
local function download(url: string, path: string)
    local response = await(http.request({method = "GET", url = url}))
    if response.statusCode ~= 200 then
        response.body:close()
        error("Download failed: HTTP " .. tostring(response.statusCode))
    end
    local output = fs.open(path, "w")
    output:write(response.body)
    await(output:close())
    return {path = path, size = await(fs.stat(path)).size,
        url = await(fs.signedGetUrl(path))}
end
```

Use separate credential-free manifest routes for signed storage URLs. Do not copy
API bearer headers to an unrelated download origin. A failed transfer can leave a
partial destination; neither a timeout nor cancellation rolls back written bytes.
`readAll()` is appropriate for bounded JSON, not for transferring large files.

### Raw and multipart uploads

```lua
local function upload(path: string)
    return responseJSON(await(http.request({
        method = "POST", url = "https://api.example.com/files",
        headers = {["Content-Type"] = {"application/octet-stream"}},
        body = fs.open(path, "r"),
    })), "upload")
end

local function uploadMultipart(path: string, filename: string)
    local body, contentType = http.multipart({
        {name = "file", filename = filename, contentType = "application/pdf",
         body = fs.open(path, "r")},
        {name = "description", body = "Quarterly report"},
    })
    return responseJSON(await(http.request({
        method = "POST", url = "https://api.example.com/files/upload",
        headers = {["Content-Type"] = {contentType}}, body = body,
    })), "uploadMultipart")
end
```

These uploads transfer ownership of the input Reader/File to the consumer.
Multipart construction returns a native Reader and a generated boundary; use its
returned Content-Type unchanged. Do not hand-build multipart bodies by loading
whole files into Lua strings or staging duplicate files.

### File metadata, text lookup and compression

```lua
local present = await(fs.exists("notes.txt"))
if present then
    local matches = await(fs.grep("TODO", "notes.txt"))
    -- matches.matches contains {path, line, text}; check matches.truncated.
end
local names = await(fs.list("reports")) -- Sorted immediate child names.

local output = fs.open("report.txt.gz", "w")
output:write(compression.gzip(fs.open("report.txt", "r")))
await(output:close())
```

Use `compression.gunzip` for an explicitly gzip-compressed file. HTTP already
handles supported Content-Encoding automatically; a `.gz` filename by itself does
not trigger decoding. File paths refer to the user's execution session, not the
server's general filesystem. Close files after explicit reads and seeks too.

### Bounded independent work

```lua
local responses = awaitAll({
    http.request({method = "GET", url = "https://api.example.com/profile"}),
    http.request({method = "GET", url = "https://api.example.com/settings"}),
})
local profile = responseJSON(responses[1], "getProfile")
local settings = responseJSON(responses[2], "getSettings")
```

Use a small, fixed or explicitly bounded group. Results stay in input order and
carry `n`, even when some are nil. Ordinary rejection does not cancel siblings.
Consume or close every successful response body. For fallible groups that need
to recover and continue, retain the original operation handles and inspect their
outcomes; otherwise let the invocation fail and release its resources. Timeouts
cancel unfinished work but cannot undo completed provider changes.

### Native database queries

A database connector uses its selected native protocol instead of HTTP. Bind its
host, credentials and verified TLS in the manifest. Here is a Postgres example;
MySQL uses `?` and ClickHouse named placeholders such as `{id:String}`:

```lua
local function findProject(id: string)
    assert(id ~= "", "id must be nonempty")
    local result = await(db.query({
        sql = "SELECT id, name FROM projects WHERE id = $1",
        params = {id}, maxRows = 1,
    }))
    return result.rows[1]
end
```

Parameterize values and keep transport credentials out of arguments. Do not infer
write authorization from a SQL string or a function name. Gate mutation exports
with effective `config.access` and let the database enforce its own permissions.

## Publish a Hub publication

A repository commit is source, not a live catalog entry. In Houston's Hub,
register the repository URL, a revision and the path to its `houston.json`.
Publication resolves the bundle and private imports, validates the manifest,
checks configured Lua exports/help, type-checks the implementation and runs its
fixtures. Resolve those failures before making the connector available to users.
Hub refreshes registered branches, so every validated push becomes the latest
release. Existing connections move to it unless its configuration shape changed:
a `config`, `publisher` or auth field was added or removed, or changed its type,
requirement, options or condition, or an auth method was added, removed or changed
its type or condition. Those connections must be set up again. Every other change
applies without setup: labels, defaults, limits, OAuth endpoints and scopes,
`proxy` rules, documentation and Lua, even when it changes a connector's API.

Use `README.md` for the account user's overview and `SETUP.md` for connecting an
account to that registered connector. Callable signatures and examples belong in
Lua `help()`. Keep publisher instructions in this root guide, even when they are
provider-specific. Use the provider's official icon, and record attribution here.

The shared `assets` package validates icons in both the bundle checker and Houston.
SVGs may contain embedded stylesheets (including dark-mode media queries), inline
styles, and local fragment references. Scripts, event handlers, external resources
and stylesheet imports remain forbidden. CSS escapes and resource-producing CSS
functions are conservatively rejected. Serve accepted images with the package's
content security policy so inline CSS works while directly opened SVGs stay
sandboxed. This support requires a Houston deployment using the shared validator;
older deployments still reject style elements.

A publisher adds the GitHub source to the Hub, producing a `HubPublicationID`
(`hub_publication_id` in APIs and the database). An admin adds instances of that
publication to an organization or personal account, producing separate
`connection_id` values. Each instance owns its settings and credentials.

For a connection-owned OAuth client, declare client ID and secret as connection
config fields and reference them from the authentication method. Houston reserves
a callback before consent: `<Houston public URL>/oauth/connections/<callback-id>/callback`.
The callback maps to one connection after authorization and remains stable on
reconnect. Include provider application setup in account-user `SETUP.md`, since the
connection admin owns that setup. Publishing such a bundle requires no OAuth client
credentials.

For a publisher-owned OAuth client, declare client ID and secret as publisher
fields instead. Register `<Houston public URL>/oauth/connectors/<hub-publication-id>/callback`
as a redirect URI in the provider application, then enter its client ID and secret
in the publication's publisher settings. Every connection of the publication uses
that redirect, and the connection form shows no callback or client fields.

When a bundle needs a new runtime or manifest capability, merge and deploy the
Houston change before registering a release that uses it. Keep the source release
and required runtime change linked in the PR so operators can apply them together.

### Publishing the Google connectors

Register repository `https://github.com/aibakery/houston-hub`, revision `main`, and
the manifest paths `connectors/gmail/houston.json`, `connectors/gcalendar/houston.json`
and `connectors/gdrive/houston.json`. The bundles use Houston's async HTTP and file
runtime and a publisher-owned OAuth client, so users only choose an access level and
select **Connect with Google**.

In the Google Cloud project that owns Houston's client:

1. Enable the Gmail API, Google Calendar API and Google Drive API.
2. Configure the OAuth consent screen (External) with Houston's name, logo, home
   page, privacy policy and authorized domain, and declare the scopes below.
3. Create a **Web application** OAuth client. Add each publication's redirect URI,
   `<Houston public URL>/oauth/connectors/<hub-publication-id>/callback`, to its
   authorized redirect URIs.
4. Enter the client ID and secret in each publication's publisher settings.

One client can serve all three publications, or each publication can have its own
client in a separate project; the bundles work either way.

| Connector | Read-only scopes | Read and write scopes |
| --- | --- | --- |
| Gmail | `gmail.readonly` (restricted) | `gmail.modify` (restricted) |
| Google Calendar | `calendar.readonly` (sensitive) | `calendar.readonly`, `calendar.events` (sensitive) |
| Google Drive | `drive.readonly` (restricted) | `drive` (restricted) |

Every method also requests `userinfo.email` to label the connected account, and asks
for offline access so Houston receives a refresh token. Houston requires every
requested scope verbatim in Google's token response, so manifests use full scope URLs
(Google reports `email` as `userinfo.email`) and one data scope set per access level.
Restricted scopes require
Google's app verification with an annual third-party security assessment; sensitive
scopes require verification without the assessment. Until the app is verified, Google
shows an unverified-app warning and caps new users at 100. While the consent screen
is in testing, only listed test users can connect and refresh tokens expire after
seven days, so connections must be authorized again weekly.

Gmail cannot permanently delete messages: `gmail.modify` excludes it, and the
connector moves messages to Trash instead. Each connector proxies only its own API
paths: Gmail `gmail.googleapis.com/gmail/v1/users/me` and its upload path, Calendar
`www.googleapis.com/calendar/v3`, and Drive `www.googleapis.com/drive/v3` and
`/upload/drive/v3`. Bundles cannot share files, so the three `connector.lua` files
carry the same request layer; `tools/validate` checks that the copies match.

### Publishing Notion

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest path `connectors/notion/houston.json`. It requires a Houston deployment
with JSON OAuth token encoding, opaque path parameters and native
`http.multipart`. OAuth client settings belong to each connection, not this publication.

The account-user [Notion setup guide](connectors/notion/SETUP.md) explains how
to configure the connection's provider application and callback. Notion
uses configured capabilities rather than OAuth scope strings. Houston exchanges
and refreshes tokens privately; token introspection and revocation are provider
application-administration tasks, not callable connector operations.

The bundle covers 61 non-OAuth operations in the
[Data API schema](https://developers.notion.com/openapi.json) and 40 operations in
the [Admin API schema](https://developers.notion.com/openapi-adminApi.json), checked
on 2026-10-10. Its Data API version is `2026-03-11`; Admin API version is
`2026-06-01`. Legacy database queries are superseded by data sources. Webhook
subscriptions are configured in Notion's developer portal because it exposes no
subscription-management REST endpoint.

Notion's icon is the official mark from [notion.com](https://www.notion.com/),
retrieved 2026-10-10. Its SVG paths are unchanged and its CSS fill is resolved to
black. Notion owns the mark. Credential-free storage rules cover documented Notion
file buckets and observed regional Notion storage hosts. Review any newly used
storage origin before extending those rules; never inject a Notion API token into
storage requests. Opaque path matching is scoped to property IDs and signed
storage keys, leaving literal route prefixes and other parameters strict.

### Publishing IMAP

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest path `connectors/imap/houston.json`. It requires a Houston deployment
with the native `imap` protocol. Each connection supplies its own server,
username and password; the [account setup guide](connectors/imap/SETUP.md) covers
app passwords and unsupported providers. The connector reads and organizes mail;
sending needs SMTP, which is a different protocol. The envelope icon is drawn for
this bundle, since IMAP is a protocol without an owner's mark.

### Publishing Mercury

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest path `connectors/mercury/houston.json`. The bundle uses the existing
manifest v1 and async HTTP/file runtime, including native multipart uploads;
no Mercury client registration or publisher credentials are needed.
The [account setup guide](connectors/mercury/SETUP.md) covers API tokens and
Mercury's IP requirements for write permissions.

The connector covers all 73 non-OAuth operations in Mercury's official
[API index](https://docs.mercury.com/llms.txt), checked on 2026-10-10. The endpoint
links in configured Lua help point to the reviewed OpenAPI definitions. This
includes the dedicated Vault host, enabled only by the connection's explicit
card-details option. SAFE endpoints expose reads and PDF downloads, not SAFE
creation or signing. OAuth onboarding/exchange is separate credential management
and is not exposed. The token connector targets production, not the sandbox.

Attachment APIs return signed URLs without specifying a stable storage allowlist.
The connector preserves those links rather than granting credentials to arbitrary
storage hosts. Statement, invoice and SAFE PDFs use documented API download
routes. Webhook configuration is supported, but Houston does not become a webhook
receiver for the caller; use a receiver you control.

Mercury's icon is the official SVG from [mercury.com/icon.svg](https://mercury.com/icon.svg),
retrieved 2026-10-10. Its dark-mode style element is removed for Houston's SVG
allowlist; the original paths and explicit fill are preserved. Mercury owns the mark.

### Publishing LinkedIn

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest path `connectors/linkedin/houston.json`. The bundle uses the existing
manifest v1 and async HTTP/file runtime and a publisher-owned OAuth client, so
users only choose an access level and select **Connect with LinkedIn**.

In the [LinkedIn Developer Portal](https://www.linkedin.com/developers/apps), with
the LinkedIn Page that represents Houston:

1. Create Houston's app with its name, logo and privacy policy URL. LinkedIn shows
   these on the consent screen.
2. On the **Products** tab, add **Sign In with LinkedIn using OpenID Connect** and
   **Share on LinkedIn**. Both are self-serve and granted immediately.
3. On the **Auth** tab, add the publication's redirect URI,
   `<Houston public URL>/oauth/connectors/<hub-publication-id>/callback`, under
   **Authorized redirect URLs for your app**.
4. Enter the **Client ID** and **Primary Client Secret** in the publication's
   publisher settings.

An **Invalid scope** error during authorization means the app lacks one of those
products; a redirect error means the redirect URI differs from the one registered.

LinkedIn enforces daily limits per member and per app. Member limits are the same
as with a connection's own app; app limits are shared by every connection and
reset daily. The app's **Analytics** tab shows usage against both.

Every connection now acts through Houston's app, so one connection's abuse puts
all LinkedIn connections at risk: LinkedIn can restrict or revoke the whole app,
not just the offending member. Houston does not yet limit connector traffic
itself, so it must add, before broad rollout:

- per-connection caps on writes (posts, image uploads and deletions) well below
  LinkedIn's member limits, with a minimum spacing between posts so a looping
  agent cannot publish in bursts;
- a cap on total writes across connections, kept well below the app limit;
- refusing further calls for a connection after LinkedIn returns `429`, until its
  daily window resets, rather than letting agents retry;
- alerts on connections approaching their caps, and a way to pause one quickly.

The publisher settings form appears once the publication syncs a release that
declares them; until they are saved, LinkedIn cannot be connected. Connections
created while client settings belonged to each connection ask to be set up again;
connecting with LinkedIn once moves them to Houston's app, and their own LinkedIn
apps can be deleted afterwards.

The connector covers the self-serve **Sign In with LinkedIn using OpenID Connect**
(`openid`, `profile`, `email`) and **Share on LinkedIn** (`w_member_social`)
products, checked on 2026-10-12. Read-only connections request only the OpenID
scopes and expose the member profile from `/v2/userinfo`. Read-write connections
add text, article and image posts and post deletion through the versioned
[Posts](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/posts-api)
and [Images](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/images-api)
APIs, pinned to `LinkedIn-Version: 202609`. Move that version forward before
LinkedIn sunsets it, about a year after release. Reading posts, comments and
organization pages needs restricted LinkedIn partner programs and is not exposed.

LinkedIn joins requested scopes with commas, and its token responses report
granted scopes the same way, as in LinkedIn's official
[API client](https://github.com/linkedin-developers/linkedin-api-js-client); the
manifest therefore sets `scope_separator` to `,`. Ordinary apps receive 60-day
access tokens without refresh tokens, so the method does not require refresh and
users reauthorize when access expires. Image uploads go to the signed
`www.linkedin.com/dms-uploads` URL returned by the Images API, which LinkedIn
documents with the member's bearer token.

LinkedIn's icon is the official In logo (`LI-In-Bug.png`) from the
[LinkedIn brand downloads](https://brand.linkedin.com/downloads), retrieved
2026-10-12. It is cropped to the In square, omitting the registered-trademark
symbol, then scaled proportionally and centered on a transparent 1024×1024 canvas
to meet the PNG icon contract, without other changes. LinkedIn owns the mark.

### Publishing WooCommerce

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest path `connectors/woocommerce/houston.json`. It requires a Houston deployment
that renders templated HTTP proxy hosts. No publisher settings or provider app are
needed: each connection enters its store domain and a WooCommerce REST API key, as
the [account setup guide](connectors/woocommerce/SETUP.md) describes.

The connector covers the WooCommerce REST API v3 resources in the
[official reference](https://developer.woocommerce.com/docs/apis/rest-api/v3/),
checked on 2026-10-13: orders, notes, refunds and order actions; products,
duplication, variations, attributes, terms, categories, tags, shipping classes,
reviews and custom field names; customers, coupons, reports, taxes, webhooks,
settings, payment gateways, shipping zones and methods, system status and data.
Updating shipping zone locations is omitted because its body is a bare array.
Requests use HTTP Basic authentication with the consumer key and secret over HTTPS.
The proxy allows only `/wp-json/wc/v3/*` on the connection's store domain.
Read-write connections may use it all; read-only connections may only GET the listed
non-sensitive resources, because settings, payment gateways and webhooks return
credentials and secrets. The read-only rule also strips WordPress's
`X-HTTP-Method-Override` header. WordPress reads `_method` and `rest_route` from any
query string too, which could change a request's method or route, and the proxy
cannot filter queries: the connector therefore accepts only plain WooCommerce query
parameter names. Stores must use pretty permalinks at the domain root.

WooCommerce's icon is the official Woo logo (`Woo_logo_color.svg`) from the
[brand assets](https://woocommerce.com/brand-and-logo-guidelines/), retrieved
2026-10-13. Its paths and purple fill are unchanged; the style element is replaced
by an equivalent fill attribute and the view box is padded to a centered square.
WooCommerce and Woo are trademarks of Automattic.

### Publishing Cal.com

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest path `connectors/calcom/houston.json`. The bundle uses the existing
manifest v1 and async HTTP runtime; no publisher settings or provider app are
needed. Each connection enters a Cal.com API key, as the
[account setup guide](connectors/calcom/SETUP.md) describes.

The connector covers a selected set of 94 user operations from Cal.com's
[API v2 OpenAPI](https://cal.com/docs/api-reference/v2/openapi.json), checked on
2026-10-14: profile and out-of-office, bookings and their attendees, guests,
recordings and transcripts, event types with booking fields, webhooks and private
links, slots and reservations, schedules, calendars and busy times, conferencing,
routing-form slot calculation, verified emails and phones, workflows, team reads
and time zones. Cal.com versions each controller with a `cal-api-version` header and
silently falls back to legacy behavior without it, so each Lua endpoint sends its
documented version; move them forward when Cal.com retires one.

Omitted on purpose: API key rotation, which would revoke the connection's own key;
credit charges; browser-based calendar, video and Stripe connection flows and Apple
calendar passwords; Insights, whose authentication is undocumented; organization
administration; the RSVP events API; and bulk webhook deletion. Not yet covered:
booking limits, selected and destination calendars, unified calendar events, CRM
sync errors, notification channels, and team administration beyond the listed
reads. Cal.com OAuth clients need Cal.com's approval, so the connector uses API keys
only. The EU host `api.cal.eu` is not documented by Cal.com and is not allowed.

Read-only connections may GET the listed routes except webhooks, whose responses
include signing secrets, and may POST only to the routing-form slot calculation,
which saves nothing.

Bundles cannot share files, so Cal.com, Calendly and Resend carry the same request layer:
option and query encoding, upstream failures, response decoding, and the generation of
functions and help from each endpoint table. `tools/validate` checks that the copies
match and that each manifest allows exactly the table's routes, with writes only on
read-write connections.

Cal.com's icon is the official square mark (`cal-logo-square-black.svg`) from the
[brand kit](https://cal.com/brand), retrieved 2026-10-14, unchanged. Cal.com® and
Cal® are registered trademarks of Cal.com, Inc.

### Publishing Calendly

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest path `connectors/calendly/houston.json`. The bundle uses the existing
manifest v1 and async HTTP runtime. Connections use a personal access token or
their own Calendly OAuth app; the [account setup guide](connectors/calendly/SETUP.md)
covers both and the scopes to select. No publisher settings are needed.

The connector covers 63 of the 65 operations in Calendly's
[API v2 OpenAPI](https://developer.calendly.com/openapi/calendly-api.json), checked
on 2026-10-14. It omits the two Enterprise data-compliance deletions, which
irreversibly erase invitee and event data, and the undocumented operations of the
older Stoplight specification, such as account deletion. Calendly has no endpoint
to delete event types or reschedule meetings.

OAuth uses `auth.calendly.com` with HTTP Basic client authentication and PKCE. Access
tokens last two hours and refresh tokens rotate on every use, so the method requires
a refresh token. Read scopes are always requested and read-write connections add the
write scopes, so narrowing a caller without write access to read-only keeps a granted
scope set. Calendly documents only `"scope": "default"` in token response examples;
Houston fails activation when a returned scope list lacks a requested scope, so
confirm one live authorization and refresh before announcing the OAuth method.
Personal access tokens carry the scopes chosen when they were created. Both methods
share the same proxy rules, which allow only the listed routes on `api.calendly.com`;
writes require read-write access.

Calendly's icon is the current square mark served at
[calendly.com/media/favicon/icon.svg](https://calendly.com/media/favicon/icon.svg),
retrieved 2026-10-14, unchanged; its gradient uses a local fragment reference.
Calendly owns the mark.

### Publishing Dropbox

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest path `connectors/dropbox/houston.json`. The bundle uses the existing
manifest v1 and async HTTP/file runtime. OAuth client settings belong to each
connection: the [account setup guide](connectors/dropbox/SETUP.md) covers creating a
scoped Dropbox app, its permissions and the callback URL. No publisher settings are
needed.

The connector covers 69 user routes of the [Dropbox API v2
specification](https://github.com/dropbox/dropbox-api-spec), checked on 2026-10-14:
account and space usage; file metadata, listing, change cursors, search, revisions,
temporary links, downloads, zip downloads, exports, previews and thumbnails;
uploads, folders, moves, copies, deletes, restores, URL saves and the batch move,
copy and delete jobs; shared links; shared folder and file membership; and file
requests. It also keeps the cross-provider `statFile` lookup. Omitted on purpose:
routes the specification marks as preview or deprecated, except `files/export`, the
only way to read Paper docs; upload sessions, so uploads stop at Dropbox's 150 MiB
single-request limit, since larger files would need chunked uploads within one
call's native-call, memory and time budgets; long polling on
`notify.dropboxapi.com`; file locks, tags, properties and templates; contacts,
profile photos and team administration, which needs a team app; permanent deletion,
which needs a team scope, and routes behind private scopes. Not yet covered: folder
creation and thumbnail batches, copy references, temporary upload links, account
batches and feature values, shared folder and file policies, folder ownership
transfer, file member updates and batch lookups, and file request counts and bulk
deletion.

Every Dropbox route is a POST, so the proxy cannot tell reads from writes. As in
Google Drive, one rule injects the token into `/2/*` on `api.dropboxapi.com` and
`content.dropboxapi.com`, keeping it off the OAuth token endpoint. Read-only
connections request only read scopes, so Dropbox refuses their writes; callers
narrowed to read-only on a read-write connection get only the read exports. Read
scopes are always requested and read-write connections add the write scopes, so that
narrowing keeps a granted scope set. Dropbox lists granted scopes in its token
response, and Houston refuses an authorization that lacks a requested one. Download
and upload routes send their argument in the `Dropbox-API-Arg` header, which Dropbox
requires to be ASCII: the connector escapes other characters as JSON `\u` escapes.

Dropbox's icon is the existing blue Dropbox mark, unchanged and shared with Houston's
app marks through the central vendor-asset registry. Dropbox owns the mark.

### Publishing Resend

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest path `connectors/resend/houston.json`. The bundle uses the existing
manifest v1 and async HTTP/file runtime, including native multipart uploads; no
publisher settings or provider app are needed. Each connection enters a Resend API
key, as the [account setup guide](connectors/resend/SETUP.md) describes.

The connector covers 103 operations of Resend's
[OpenAPI](https://github.com/resend/resend-openapi) 1.5.1 and
[API reference](https://resend.com/docs/api-reference/introduction), checked on
2026-10-15: sent and received emails, their attachments, batch and scheduled sends,
sharing and metrics; domains and domain claims; API key listing; templates;
contacts, contact imports and their segments and topics; broadcasts with their
recipients and clicked links; webhooks with their events and replays; segments;
topics; contact properties; logs; automations and their runs; events; and
suppressions. Resend's API is unversioned, so there is no version pin.

Omitted on purpose: creating, renaming and deleting API keys, since creation returns
a credential and deletion could revoke the connection's own key; OAuth grants and
the OAuth endpoints; Inboxes and segment metrics, which are in private beta; the
deprecated audiences; `GET /usage`, which has no reference page; the `POST /email`
send aliases; and the SDK-only `x-batch-validation` header. The connection uses API
keys. Resend also offers OAuth 2.1 with PKCE, `full_access` and `emails:send` scopes,
15-minute access tokens and rotating refresh tokens; an OAuth method could later
replace pasted keys.

Read-only connections may GET the listed routes except single webhooks, whose
responses include signing secrets, and single logs, which contain logged request and
response bodies. The read-only rule also strips method-override headers. A separate
credential-free rule allows GET on `outbound-cdn.resend.com` and
`inbound-cdn.resend.com`, the documented hosts of signed attachment links, so the
connector can save attachments as session files. Resend does not document the host
of a received email's raw `.eml` link, so the connector returns that link without
downloading it.

Resend's icon is the official black icon (`resend-icon-black.svg`) from the
[brand page](https://resend.com/brand), retrieved 2026-10-15, unchanged. Resend
owns the mark.
