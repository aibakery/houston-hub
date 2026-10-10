# Writing clear Luau connectors

These are optional recommendations, illustrated by the
[Fastmail connector](../connectors/fastmail/connector.lua). They are not additional
publication rules or a style checklist enforced by CI. Contributors may choose a
different structure when it makes their connector easier to understand. The
[authoring guide](authoring.md) describes the actual runtime and bundle contract.

## Start with the interface

Keep the public operations easy to find, with clear function signatures and
examples in `help()`. Callers pass ordinary tables with meaningful keys; they do
not need to import types. Local Luau types can check parameter and result shapes
inside the implementation without adding exported types or a separate interface
declaration that duplicates the functions. Use annotations where they clarify the
code, and avoid casting whole implementations to `any` to silence the checker.

Use a simple ID argument for a simple lookup. Prefer a typed options table when a
call has several related choices: named fields explain what each value means and
leave room for optional additions without positional placeholders.

```lua
-- A caller can see what both values mean.
local message = mail.getMessage({
    id = "message-123",
    maxBodyValueBytes = 4096,
})
```

Keep established positional forms working when introducing named forms. Normalize
both forms once near the operation boundary, then use one implementation. Do not
add an options table to every tiny helper simply to reduce its parameter count;
two clear scalar arguments are often simpler.

Use precise types for your own records and public parameters. Keep dynamic JSON
handling close to the provider boundary; `any` there can be practical, but it
should not spread through unrelated helpers. A type annotation does not validate
an upstream response or untyped caller. Check IDs, integer bounds, required fields
and provider confirmations before using them.

The connector's pure `help()` is its callable documentation. Keep signatures,
defaults, pagination, result shapes and mutation behavior accurate, and derive
the listed operations from the configured exports. Keep the bundle README focused
on what people can do with the connector.

## Keep state small and its lifetime explicit

Use `local` for helpers and implementation details. An upvalue is a local captured
by a function: it is useful for stable constants and small shared context, but it
also keeps the captured value reachable for as long as that function lives.

Houston initializes a fresh connector VM for each operation invocation. A small,
lazy session cache can avoid repeated discovery requests within that invocation;
it is not a cache across calls or accounts. Retain only the session fields later
steps need. Avoid capturing full HTTP responses, message bodies or attachment
bytes in long-lived closures. Initialization and `help()` stay free of network
requests.

Name meaningful protocol constants, repeated property lists and limits once.
Use `table.freeze` for shared tables that should never change, remembering that it
is shallow. Construct fresh mutable request records for each request rather than
changing a shared template.

Luau optimizes immutable upvalues and many standard-library accesses. Prefer
readable `string.format` and `table.concat` calls over mechanically creating a
local alias for every built-in. Measure before making performance-driven changes;
see Luau's [performance notes](https://luau.org/performance/).

## Reduce work before tuning syntax

Request only the fields an operation uses. An attachment listing needs metadata,
not message bodies. Avoid a mailbox lookup when a query needs no folder resolution
or default spam/trash exclusions. Keep provider ordering and requested ID ordering
explicit when they differ.

Process one bounded batch at a time instead of constructing every batch first.
This limits temporary allocations, though a function returning all messages still
retains all its results. Expose pagination where appropriate, and let callers
choose smaller pages and bodies. A provider's per-body limit does not bound the
entire response.

Use `body = fs.open(path, "r")` for uploads and `output:write(response.body)`
followed by `await(output:close())` for downloads. Return session paths and
awaited signed URLs, avoiding an extra in-memory representation of file bytes.
Do not read a file into a Lua string just to upload it, or add a second base64/MIME
implementation when the provider already accepts structured messages.

`await(http.request(...))` returns final headers and a body Reader. Read JSON
explicitly with `await(response.body:readAll())`; inspect `statusCode` and close
unneeded bodies. Request and response headers contain arrays of strings.
Sequential batches keep in-flight work predictable. Account for
the invocation's native-call, memory, frame-size and execution budgets, including
file operations; see [execution and waiting](authoring.md#execution-and-waiting).
An interrupted operation cannot roll back a write already accepted upstream.

Build strings with a parts array and `table.concat` when collecting many pieces.
Bound error snippets before transforming them; an error message should not require
copying an entire large response. Avoid retaining raw body representations after
producing the normalized body.

## Share behavior, keep provider details visible

Extract repeated behavior with a clear purpose: JMAP invocation/error handling,
ID normalization, folder resolution or mutation confirmation. Keep the provider's
method name and meaningful arguments visible at each call site. A small private
helper usually suffices; a generic framework or a module per helper rarely does.

Preserve JSON semantics. Houston's JSON null sentinel is truthy, and empty `{}`
encodes as an object. Use `json.decode("[]")` for arrays that may be empty. Remove
optional null fields only where that interpretation is appropriate: in a JMAP
update result, a null value can be a successful confirmation.

Treat HTTP success and provider success separately. Validate method responses,
per-item errors and required creation/update confirmations. Preserve useful
operation context. A partial mutation or ambiguous send must not be retried
automatically; explain that possibility in help.

## Verify behavior, not a preferred spelling

Use fixtures that execute the real connector and assert the requests and results
that matter: named and positional arguments, empty arrays, JSON nulls, pagination,
ordering, missing scopes, malformed responses, partial mutations and attachment
streaming. For memory improvements, check that unnecessary fields or repeated
requests disappear; avoid asserting exact source text or incidental helper names.

Run the existing Go validator with the runtime and Luau analyzer described in the
[authoring guide](authoring.md#tests-and-publication):

```sh
go run ./tools/validate connectors/fastmail
```

This runs the existing manifest, type and behavior checks. It adds no style gates.
