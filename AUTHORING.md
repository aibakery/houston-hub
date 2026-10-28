# Create and publish a Houston connector

This guide covers the shared connector contract and authoring workflow. Connector
folders contain bundles and account-user documentation. Publishing follows the
settings declared in `houston.json`; see
[Publish a Connector on Houston Hub](#publish-a-connector-on-houston-hub).
For a shorter overview, see [Build a connector](https://ok-houston.com/docs/connectors).
To build with an agent, install the
[houston-connector skill](https://ok-houston.com/docs/connectors/SKILL.md) as
`.claude/skills/houston-connector/SKILL.md`.

Start with the [Fastmail](connectors/fastmail/connector.luau) and
[Notion](connectors/notion/connector.luau) implementations. Fastmail demonstrates
provider-specific helpers and typed records; Notion demonstrates a broad REST
surface sharing a small request layer.

## Workflow

1. Read the provider's official API and authentication documentation. List the
   operations, required permissions, pagination and file-transfer behavior.
2. Create a bundle with a manifest, pure-initializing Luau entrypoints, official
   provider icon, account-user README and SETUP, and behavior fixtures.
3. Implement operations using the runtime examples below. Keep credentials in
   manifest injection rules, and derive both exports and help from effective access.
4. Validate the real bundle with the Go validator and current Houston runtime.
5. Commit and push the source, then register its repository, revision and manifest
   path in Houston's Hub. Connection admins configure account credentials when adding a connection.
6. Connect a test account using the same flow account users see. Check discovery,
   read-only behavior, paging and a provider-confirmed write on disposable data.

Use [runtime examples](#runtime-examples), [Luau practices](docs/luau-practices.md),
[validation](#tests-and-publication), and [publication](#publish-a-connector-on-houston-hub)
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
  connector.luau
  icon.svg
  tests/behavior.luau
```

Name Luau sources `.luau`; Houston also accepts `.lua` for modules and tests.
`files` is a required nonempty array of entrypoints. Private imports use exact
canonical paths relative to the manifest, such as `require("lib/pagination.luau")`.
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
  "files": ["connector.luau"],
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
Houston sends `User-Agent: Houston (+https://ok-houston.com)` unless the
connector sets one; set it only when the provider mandates a format. It retries an HTTP 429 at most twice, waiting as
`Retry-After` asks when that is 5 seconds or less, or 1 and then 2 seconds when it is
absent or unreadable; a longer `Retry-After`, a third 429 or a streamed request body reaches the
connector unchanged. Nothing else is retried.

The shared `assets` package validates icons in both the bundle checker and Houston.
SVGs may contain embedded stylesheets (including dark-mode media queries), inline
styles, and local fragment references. Scripts, event handlers, external resources
and stylesheet imports remain forbidden. CSS escapes and resource-producing CSS
functions are conservatively rejected. Serve accepted images with the package's
content security policy so inline CSS works while directly opened SVGs stay
sandboxed. This support requires a Houston deployment using the shared validator;
older deployments still reject style elements.

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
invocation to 256 native calls, including file operations, 64 MiB of Luau memory,
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
the prefix. It fails when the Reader is closed, cancelled (including an await
timeout) or already in use, when the limit is not a positive integer (the Reader
then stays open, so pass a constant), or when a limit above 128 MiB or the
invocation's read budget refuses the call (the Reader is then closed).
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
Decoding is lazy. The server decodes connector HTTP responses before credential
redaction. Received Content-Encoding and Content-Length headers remain available
as upstream metadata; do not decode again or use that length as a decoded size.
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

Houston restricts effective config using current caller grants; Luau selects the
exports from that config. Discovery is recomputed from the
current connection release, settings and authentication facts on each request;
existing client instances must be rediscovered to refresh their function list.
Invocation still checks current configuration and grants before dispatch.
Document signatures, defaults, results and mutation behavior in the connector's
Luau `help()` function, exposed as `instance.help()`. Teach callers to read help, never
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
OAuth exchanges and refreshes default to form-encoded bodies. Providers can select `token_encoding: "json"` and supply literal `token_headers`
when their token endpoint requires them (see the
[Notion manifest](connectors/notion/houston.json)). These headers cannot replace authentication or
transport framing headers. Credentials still stay outside Luau.

An OAuth method whose provider publishes sign-in button guidelines sets `brand`
to `google`, `microsoft` or `dropbox`. Houston then renders its authorize button
as "Continue with <Provider>" with the provider's official mark and colors, as
Google's OAuth verification requires (see the
[Google Sheets manifest](connectors/gsheets/houston.json)). Without `brand`, the
button stays Houston's primary "Authorize account".

An omitted `auth` map permits root-secret injection without a synthetic method.
Fields activate through the bounded `if` operations `is`, `isDefined`, and `and`.
Dependencies precede presentation order. Missing required selectors are errors;
inactive saved values cannot satisfy references. Templates use explicit owners:
`publisher.name`, `config.name`, `auth.token.token`, or an OAuth method's
`auth.oauth.access_token`. Fallback `||` is available for values, not predicates.

Use `multiline: true` on a plain string field for a textarea. Add `format: "json"`
for syntax highlighting and live JSON syntax validation. The exact string is
preserved, but defaults and submitted values must contain valid JSON. Any JSON
value is accepted, including arrays and scalars; an optional field may be omitted,
but an explicitly empty string is invalid. Connector code must still validate the
structure and meaning before using it. Multiline fields cannot be secret, masked, or choices.
The same metadata works for publisher, connection, and manual-auth settings.
Conditional required fields are required only while active, for example:

```json
"folder_rules": {
  "type": "string",
  "label": "Folder permissions",
  "if": "{{ is config.mode \"custom\" }}",
  "required": true,
  "multiline": true,
  "format": "json"
}
```

Inactive fields are omitted from forms and runtime config; a save cannot submit
values for them. Previously saved inactive values can be reused when reactivated.
Unsaved edits to a field are discarded when its condition becomes inactive.

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
unconditional string setting, as in the [WooCommerce manifest](connectors/woocommerce/houston.json).
Houston renders it when resolving each connection; the result must be one exact
origin, so wildcards, schemes and paths in the setting are rejected. Luau builds its
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

For providers that only accept query credentials, use
`"action": {"query": {"access_token": "{{auth.token.token}}"}}`. This requires
a Houston deployment supporting query injection. The server selects the rule
using the original request, then renders and URL-encodes its query values.
Names match `[A-Za-z][A-Za-z0-9_-]*` and are case-sensitive. All existing values
for each configured name are replaced; unrelated values are preserved and
malformed queries are rejected. Query templates have the same secret and
publisher-recipient restrictions as headers. Keep credential names out of the
connector's arguments and URLs: secrets and prepared URLs never enter Luau.
Echoed credentials are redacted from response headers and decoded bodies.
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
See the [Fastmail manifest](connectors/fastmail/houston.json) for separate
authenticated API routes and credential-free download hosts.

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
the [IMAP connector](connectors/imap/connector.luau) documents each command and its
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

The connector Luau is the sole authority for configured functions and their help.
Return only functions enabled by the effective public configuration. Houston
clamps canonical `config.access` modes to `read-only` for callers without a current
write grant. A `custom` mode retains its active policy settings and must intersect
each operation's policy with immutable `houston.access` (`read-only` or `read-write`).
The same configured Luau serves discovery and execution. Native dispatch
rechecks current connection access and the effective configuration before each
transport request. Do not infer permission from function names or HTTP verbs.
Provider and database grants remain authoritative.

Export a pure `help()` function returning a nonempty string for precisely those
configured functions. Build the text from the same export table, including their
arguments, return shapes, pagination, and meaningful provider caveats. Houston
evaluates help with native transports disabled and excludes it from the callable
operation list. Help must be deterministic and must never probe credentials or
call a provider. Keep README documentation for humans; agent help comes from Luau.
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
User-facing documentation and forms must not teach agent usage: no Lua/Luau,
`help()`, callable function names, request or response shapes, pagination examples,
or MCP instructions. This applies to README content and frontmatter, `SETUP.md`,
inline descriptions and setup, and configuration labels and descriptions.
Credential names and provider permissions belong in setup when people need them
to connect. Keep these surfaces focused on capabilities, access choices and
account setup. Agents discover usage through MCP initialization, system
instructions and the connector's Luau `help()`; preserve programming examples
and caveats there.

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
validator selects the bundles migrated to the current runtime; see the maintained
list in [README.md](README.md). An explicit catalog directory validates all its
bundles.

Set `HOUSTON_RUNTIME` to a newly built Houston service runtime and put the pinned
`luau-analyze` on `PATH`. A fixture returns a table with `scenario`, optional
public `config` overrides, optional `configure`, and `run`. The scenario contains
synthetic `publisher`, root `config`, `auth_method`, and selected `auth_config`
inputs, plus optional `caller_access` (`read-only` or `read-write`). Without it,
caller access defaults to read-write only for canonical read-write configuration;
custom policy fixtures default to read-only. Explicit caller access is intersected
with connection access before resolving conditional fields, preserving custom
policy. Houston resolves settings through the production manifest contract before
projecting only active nonsecret root values into the fixture VM. Include every
declared auth method, enabled proxy rule, and intended enabled/disabled surface.
Eligibility coverage does not establish which rule wins; matcher tests separately
cover rule order, request filters, and action behavior.
Fixtures assert actual provider arguments, responses and behavior. Publication
checks deterministic configured exports and help, and requires fixture scenarios
covering each authentication method and enabled proxy rule. Access is determined
by the configured Luau exports; there is no operation-access metadata sidecar.
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
`read-only`, `read-write`, and `custom`. An optional field without an explicit default
defaults to `read-only` before conditional fields, OAuth scopes, and proxies are
resolved. Required fields still require a value, and explicit null inputs are
invalid. When undeclared, Houston supplies `read-only`.
The publication type checker exposes this reserved field even if the manifest
does not declare a configurable Access setting.

Only connector VMs receive immutable `houston.access`, the effective caller grant.
For `custom`, retain and enforce the configured policy even for read-only callers;
never substitute unrestricted account-wide reads. Custom write exports require
both `houston.access == "read-write"` and a policy permitting the write.

`houston.seal(value)` returns an opaque encrypted token, and `houston.unseal(token)`
returns the original plain JSON value. These synchronous connector-only helpers
are intended for provider cursors and job handles that must carry an authorized
folder or operation between calls. They are forbidden during initialization and
`help()`, count toward the native operation limit, and use normal cancellation.
JSON values are limited to 64 KiB encoded, tokens to 96 KiB. Tokens are bound to
the connection, release, and settings/authentication generations; changed access
configuration or account authorization invalidates them. Opening a token does not
authorize its operation: validate its purpose and current caller/folder permissions
again before using its provider handle. Keep tokens outside errors and logs.

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
such as `..` (or only dots and spaces, also before a `;`, `?` or `#`), `/`, `\`, `%`, control characters, values whose
NFKC form contains those (such as U+FF0E), invisible format characters, best-fit
separator look-alikes (such as U+00A5), invalid UTF-8 or more than 16 KiB, naming `name`
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
whole files into Luau strings or staging duplicate files.

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

## Publish a Connector on Houston Hub

Use the connector's `houston.json` as the source of truth for publishing settings.
Registering source creates a Hub publication; adding that publication to an
organization or personal account creates a separate connection with its own
settings and credentials.

1. Validate the bundle using [Tests and publication](#tests-and-publication), then
   commit and push its source. If it needs a new runtime or manifest capability,
   deploy that capability before registering the release.
2. In Houston Hub, register the repository URL, revision and path to `houston.json`.
   These identify the source; they are not fields in the manifest. A repository
   commit alone does not create a catalog entry. If you choose to verify source
   ownership, follow Hub's challenge using the manifest's `verification_key`.
3. Configure the publication from the manifest's `publisher` fields. Use their
   labels, descriptions, defaults, conditions and required flags. If no publisher
   fields are declared, there are no publisher settings to enter. Secret values
   belong in Hub's settings form, never in source.
4. If an OAuth method references publisher-owned client fields, configure its
   provider application and redirect URI as described below. Connection-owned
   credentials are supplied later by each connection's admin.
5. Resolve any publication validation errors, then add a connection and follow
   its `SETUP.md`. Verify discovery, access restrictions, pagination and any
   supported authentication or file-transfer flows. Test writes only on
   disposable data with the account owner's authorization.

The manifest determines who supplies each value:

| Declaration | Configured by |
| --- | --- |
| `publisher` | The publisher, once per Hub publication |
| Root `config` | The connection admin, once per connection |
| Manual `auth.<method>.config` | The connection admin for the selected authentication method |
| OAuth `auth.<method>.client_id` and `client_secret` | The owner of the referenced fields: `publisher.*` or `config.*` |

For OAuth, read the selected method's endpoints, client references, scopes and
conditions from `houston.json`. Configure the provider application to support
those declarations; do not infer additional credentials or permissions.

- **Publisher-owned client:** register
  `<Houston public URL>/oauth/connectors/<hub-publication-id>/callback` as its
  redirect URI and enter the declared client fields in the publication settings.
  All connections of that publication share this callback.
- **Connection-owned client:** publishing requires no OAuth client credentials.
  Houston reserves a callback when connection setup opens:
  `<Houston public URL>/oauth/connections/<callback-id>/callback`. The connection
  admin registers that displayed URI in their application. It remains stable on
  reconnect. Explain this account setup in the connector's `SETUP.md`.

Hub resolves the source and private imports, validates the manifest, checks
configured exports and help, type-checks the implementation and runs its fixtures.
Registered branches refresh after validated pushes, producing new releases.
Keep required runtime changes linked in the release PR so they can be deployed
before a registered source starts using them.

Houston reuses saved connection inputs and applies defaults when adopting a new
release. Valid optional fields, inactive fields, removed fields, documentation
and Luau changes can apply without setup; saved choices take precedence over new
defaults. Missing active required inputs, invalid retained values or an
unavailable selected auth method require **Set up again**. OAuth client or
authorization changes and newly required scopes can also require setup; narrower
scopes preserve an existing grant. Setup retains reusable credentials, and secret
values never become public inputs automatically.

Publisher inputs belong to the registration. Clear configured values before
removing publisher fields or changing their types; publication rejects those
changes while values remain. Editing saved publisher settings requires affected
connections to confirm the new settings.

Keep this workflow generic. Publisher configuration comes from `houston.json`;
account setup belongs in `SETUP.md`, the user overview in `README.md`, and callable
signatures and examples in Luau `help()`.
