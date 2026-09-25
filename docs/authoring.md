# Authoring a Houston connector

This repository is the source of truth for Houston connector definitions. Each connector has one directory under `connectors/`; Git commits version the complete catalog. Houston's hub service follows `main`, validates a complete commit, caches it in Redis, and publishes it at `https://hub.ok-houston.com/v1/catalog`. Invalid revisions leave the previous catalog available.

## Bundle layout

```
connectors/my-service/
  houston.json
  connector.lua
  icon.png             # optional, exactly 1024 × 1024
  tests/
    requests.lua
```

The default module is `connector.lua`, so omit `module` from the manifest for that filename. To use another filename, including `connector.luau`, set `"module": "connector.luau"` explicitly. Both extensions run Luau. The manifest's `id` must equal its directory name and the module's `name`. `schema_version` is the manifest format version, not a connector release version. There are no version directories. Shared transport helpers live in `helpers/`; the runtime exposes `http.lua` as `connector_http` and `sql.lua` as `connector_sql`.

Copy the closest existing connector as a starting point. `houston.json` is dashboard configuration and server policy: its title, description, setup text, authentication methods, access modes, configuration fields and protocol rules generate the connection and management screens and constrain server requests. The manifest does not export callable functions. Only the Lua module's `functions` and optional `writes` tables define the functions agents can call. `access` declares available modes, descriptions and OAuth scopes.

## Authentication choices

`auth` accepts one method object or an array of methods. Supported types are `secret` and `oauth2`. The first array entry is the default; the dashboard lets users choose another method. A method can have an `id` and display `label`. Its ID defaults to its type when that type appears only once. Give methods explicit, distinct IDs when offering two methods of the same type.

An authentication method can also override `module`, `description`, `setup`, `access`, `config_fields`, and `proxy`. Omitted fields inherit the top-level value. A supplied field replaces the entire value: access lists, configuration fields and proxy objects are never merged. For example, `config_fields: []` removes inherited fields; a `proxy` override must include its protocol and complete route policy. The connector's identity, publisher and icon stay at the top level.

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
      "registration_id": "YOUR-REGISTRATION-UUID",
      "authorize_url": "https://example.com/oauth/authorize",
      "token_url": "https://example.com/oauth/token"
    }
  }
]
```

This example is an excerpt, not a complete manifest. An OAuth method also requires the manifest's `publisher_id` to identify the organization owning that registration. Secret-only connectors do not need `publisher_id` or an application registration. Database connectors use secret authentication and declare their connection fields in `config_fields`.

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

## OAuth applications and ownership

For OAuth authentication, create a **Connector app** in your Houston organization's dashboard (`/dashboard/publishers`). Houston returns a registration ID and publisher organization ID. Put these in the OAuth method's `oauth.registration_id` and the manifest's `publisher_id`. Store the client ID and secret only in that dashboard; the public repository contains no OAuth app secrets. A registration is bound to its organization and connector slug, and the server verifies all three identifiers before using it.

The OAuth manifest describes authorization/token/profile endpoints, response paths, scopes and any required response checks. Add `https://ok-houston.com/oauth/connectors/<id>/callback` to the provider's registered redirects. Access-mode scopes must match the provider application. Rotate credentials using the same dashboard; IDs remain stable.

Official connectors use the same registration interface. Their publisher is Houston's designated official organization, `10c6c4ae-c531-4546-8ddf-7d05113f1b35`. Community connector registrations belong to their own organizations. Publication remains a reviewed pull request to this repository; adding a registration does not publish code automatically.

## Tests and contributions

Every bundle includes credential-free `tests/*.lua` or `tests/*.luau`. Each test returns a function accepting the connector module:

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

CI always checks bundle layout, manifests and icon dimensions with `go run ./tools/validate`, then downloads the public Houston CLI and runs Lua tests when it supports `test-connectors`. The layout validator uses only Go's standard library. During the initial CLI rollout, CI emits an explicit warning if Lua tests are unavailable; maintainers must run them from the implementation checkout before merging. Houston's implementation repository is private, so community PRs require no checkout credentials. Full manifest security validation and every Lua test run in the hub service before publication; missing or failing tests reject the Git revision.

Submit a pull request containing only the bundle and tests unless a reusable protocol capability genuinely needs a host change. Maintainers review domain ownership, credential injection destinations and permissions as well as functionality. After merge, the hub and API poll the new Git revision; CLI and MCP load the served module without rebuilding provider code. Roll back by reverting the connector commit on `main`.
