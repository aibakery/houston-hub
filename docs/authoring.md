# Authoring a Houston connector

The dashboard is the catalog registry; GitHub is the source of connector files. Organization admins register any public GitHub repository in **Connector Catalog**. Branch defaults to `main`, and an omitted path means `houston.json` at the repository root. Houston validates the manifest, module and declared icon, then publishes the connector immediately. Neither secrets nor verification are required. This repository provides examples, not an automatically published catalog.

## Bundle layout

```
connectors/my-service/
  houston.json
  connector.lua
  icon.png             # optional, exactly 1024 × 1024
  tests/               # optional
    requests.lua
```

The default module is `connector.lua`, so omit `module` from the manifest for that filename. To use another filename, including `connector.luau`, set `"module": "connector.luau"` explicitly. Both extensions run Luau. The manifest's `id` must match the module's `name` and be unique in the shared catalog. Its folder can have any name. In this examples repository, folder names also match IDs for the authoring tools. `schema_version` is the manifest format version, not a connector release version. There are no version directories. The runtime supplies the standard `connector_http` and `connector_sql` transport helpers. Repository code cannot replace the catalog’s shared helpers.

Copy the closest existing connector as a starting point. `houston.json` is dashboard configuration and server policy: its title, description, setup text, authentication methods, access modes, configuration fields and protocol rules generate the connection and management screens and constrain server requests. The manifest does not export callable functions. Only the Lua module's `functions` and optional `writes` tables define the functions agents can call. `access` declares available modes, descriptions and OAuth scopes.

## Authentication choices

`auth` accepts one method object or an array of methods. Supported types are `secret` and `oauth2`. The first array entry is the default; the dashboard lets users choose another method. A method can have an `id` and display `label`. Its ID defaults to its type when that type appears only once. Give methods explicit, distinct IDs when offering two methods of the same type.

An authentication method can also override `module`, `description`, `setup`, `access`, `config_fields`, and `proxy`. Omitted fields inherit the top-level value. A supplied field replaces the entire value: access lists, configuration fields and proxy objects are never merged. For example, `config_fields: []` removes inherited fields; a `proxy` override must include its protocol and complete route policy. The connector's identity, verification key and icon stay at the top level.

This excerpt gives API-key connections the default read-only module and policy, while OAuth connections can use a different module and expose writes:

```json
"access": [{"id": "read-only", "label": "Read-only"}],
"proxy": {
  "protocol": "http",
  "routes": [{
    "hosts": ["api.example.com"], "paths": ["/v1/records"],
    "methods": ["GET"], "access": "read", "auth": true
  }]
},
"auth": [
  {"type": "secret", "label": "API key", "secret_label": "API key"},
  {
    "type": "oauth2",
    "label": "Connect your account",
    "module": "account.lua",
    "description": "Read records and create records as yourself.",
    "access": [
      {"id": "read-only", "label": "Read-only", "scopes": ["records.read"]},
      {"id": "read-write", "label": "Read and write", "scopes": ["records.read", "records.write"]}
    ],
    "proxy": {
      "protocol": "http",
      "routes": [
        {
          "hosts": ["api.example.com"], "paths": ["/v1/records"],
          "methods": ["GET"], "access": "read", "auth": true
        },
        {
          "hosts": ["api.example.com"], "paths": ["/v1/records"],
          "methods": ["POST"], "access": "write", "auth": true
        }
      ]
    },
    "oauth": {
      "client_id": "{{MY_APP_ID}}",
      "client_secret": "{{MY_APP_SECRET}}",
      "authorize_url": "https://example.com/oauth/authorize",
      "token_url": "https://example.com/oauth/token"
    }
  }
]
```

This example is an excerpt, not a complete manifest. OAuth credentials reference keys you choose in Connector Secrets. A connector without shared server secrets needs no verification key. Database connectors use secret authentication and declare their connection fields in `config_fields`.

Here `connector.lua` can export a `records` function, while `account.lua` can additionally export `writes.createRecord`. Both modules return the same connector `name`; their callable functions may differ. The selected method determines the module and server policy for each connected account. Merely declaring write access or a proxy route never creates a function: each callable must be exported by the selected Lua module.

## Requests and module exports

For HTTP connectors, `proxy.routes` explicitly lists hosts, paths, methods, read/write classification and whether to inject credentials. Routes default to denial: declaring a domain does not permit every request to it. Keep permissions narrow. Use `auth: false` only for approved signed upload/download URLs that must not receive the connector credential. Manifest batch policies constrain protocol envelopes such as JMAP or multipart requests. The server supplies generic protocol transports; service-specific request construction belongs in Lua.

The module returns a table with nonempty `name`, `description`, `help`, and a `functions` table. Optional `writes` contains functions exposed only to callers with read/write access; `signatures` provides short discovery prototypes. Every function's first argument is the host-supplied context (`ctx.id`, `ctx.type`, `ctx.name`, `ctx.source_id`). There are no secrets in `ctx`. Manifest `config_fields` and stored connection configuration are not automatically mounted into Lua or exposed as `ctx.config`. If a function needs a nonsecret option, accept it as an explicit argument. The server resolves credentials and connection settings and checks permissions independently of Lua.

```lua
return {
    name = "my-service",
    description = "Read records from My Service.",
    help = "Use records() to list accessible records.",
    functions = {
        records = function(ctx)
            return connector_http.send({
                connector = "my-service", connector_id = ctx.id,
                operation = "records", method = "GET",
                path = "/v1/records", url = "https://api.example.com/v1/records",
            })
        end,
    },
}
```

## Registration, secrets and verification

In **Connector Catalog**, enter the public GitHub repository, branch (default `main`) and optional connector folder or `houston.json` path. A valid registration immediately appears in the shared Hub. Each connector ID and source location has one catalog entry, owned by the registering organization. No pull request to this repository is required. Future valid Git commits update that entry; invalid updates show an error and retain the last validated module. Removing the registration removes it from the catalog.

Admins manage optional, arbitrary key/value pairs in the separate **Connector Secrets** menu. Values are encrypted and write-only. Reference keys such as `{{MY_APP_ID}}` and `{{MY_APP_SECRET}}` in server-side config; names are your choice. Keys use letters, digits and underscores, starting with a letter or underscore. Each auth mode can reference different keys. Expansion happens once after selecting the mode; missing required keys disable that mode. A connector without shared secrets needs none of this setup.

Secrets belong to the registered catalog entry and its immutable source. Their use does **not** require a verification key. An admin may optionally request a verification challenge in Connector Catalog, then commit it as top-level `verification_key`. A matching challenge earns a **Verified** badge that proves repository control. Missing or mismatched keys remove the badge without blocking publication or secrets. Existing keys in a repository do not prevent registration or confer verification on a new entry.

Secret resolution produces a detached server configuration. The public catalog always retains placeholders, and Lua never receives resolved values. Shared secrets are not injected into Lua-callable proxy requests.

| Configuration | Secret placeholders |
| --- | --- |
| OAuth client ID/secret, authorization/token/profile URLs, authorization parameters, token parameters, token extraction paths, required response checks, auth style and scope formatting | Allowed; expanded only in a detached server configuration |
| OAuth account/scopes/config response mappings, authorization input mappings and write-scope policy | Rejected; these affect public connection metadata or runtime policy |
| Identity, descriptions, setup text, modules, access choices, connection form fields, and proxy policy (including auth overrides) | Rejected; these are public or used by the runtime |
| Lua source and module context | Never expanded; no secret values are mounted |

For custom token request fields use `auth.oauth.token_params`, for example `{"audience": "{{MY_AUDIENCE}}"}`. This is separate from `params`, which goes to the browser authorization URL. Use only values intended for the authorization provider/browser in authorization URLs, client IDs and `params`. Client secrets belong in `client_secret` or server token parameters.

Add `https://ok-houston.com/oauth/connectors/<id>/callback` to the provider’s allowed redirects. Official examples and community connectors use the same registration and secret-management flow.

## Tests and contributions

Bundles may include credential-free `tests/*.lua` or `tests/*.luau`. Each test returns a function accepting the connector module:

```lua
return function(connector)
    http.send = function(method, url, headers, body, options)
        assert(method == "GET" and url == "https://api.example.com/v1/records")
        return { status = 200, body = '{"records":[{"id":"r1"}]}' }
    end
    local result = connector.functions.records({ id = "fixture" })
    assert(result.records[1].id == "r1")
end
```

Run `houston test-connectors /path/to/houston-hub`. Each test gets an isolated Luau VM, JSON helpers and shared connector helpers. HTTP fails unless mocked. No Houston login or provider credential is needed. Tests have a five-second execution deadline and a 64 MiB VM memory budget. Cover actual request shape, pagination, decoding, provider failures and write behavior; a module-shape assertion alone is insufficient for a new feature. Existing Slack and Fastmail tests demonstrate mocked transport and file operations.

CI checks bundle layout, manifests and icon dimensions with `go run ./tools/validate`, then downloads the current public Houston CLI and runs every Lua test. An outdated runner fails the check. The layout validator uses only Go's standard library. Houston's implementation repository is private, so community PRs require no checkout credentials. Registration always validates module initialization in a bounded Luau sandbox. Supplied tests also run; failures reject the revision. A tests directory is optional.

Register your own repository from the dashboard to publish it. Pull requests to this repository are welcome for improving the examples, but merging files never creates a catalog entry automatically. GitHub commits update registered entries without rebuilding the API or CLI. Roll back by reverting the source commit.
