# FamilySearch API coverage

The connector follows the [public API reference](https://developers.familysearch.org/main/reference) and [official examples](https://developers.familysearch.org/main/llms.txt), reviewed on November 18, 2026. Named operations preserve FamilySearch operation IDs within resource namespaces and retain GEDCOM X request/response shapes. Root `help()` lists API areas; each namespace has its own operation index and focused function help. Only operations enabled by the connection's access are listed.

| API family | Coverage |
| --- | --- |
| Family Tree | Persons, conclusions, relationships, notes, sources, discussions, memories, portraits, pedigrees, search, matches, merge analysis/merge, deletion/restoration, and change history |
| User trees and genealogies | Trees, groups, tree selection, persons, relationships, sources, matching, and publishing |
| Memories | Metadata, comments, personas, artifact coverage, upload/update, and streaming artifact download |
| Sources | Source descriptions, collections/folders, references, and change queries |
| Authorities | Places and place types/groups, date standardization, name segmentation/composition, and controlled vocabularies |
| Users | Current user/person, agents, history, source folders, memories, preferred relationships, and partner-account endpoints |
| Authentication | Account OAuth with PKCE and existing tokens, separately configured for Production and Beta |

Read-only connections retain search-like POST operations, including name composition, matching, and source change queries. The deprecated partner-account acknowledgement is a write even though FamilySearch exposes it as GET. Every write requires **Write** at both discovery and transport.

Collections return one page at a time, preserving provider links and pagination headers. Writes return HTTP confirmation metadata, including entity IDs and locations where supplied. Multi-entity requests can have partial outcomes; inspect the returned data and read the affected records before retrying an ambiguous write.

## Provider and transport limits

- FamilySearch's current [compatibility review](https://developers.familysearch.org/main/docs/compatibility-review-process) does not offer historical-record search through the API. Record hints link to FamilySearch for viewing. Restricted ordinance operations require a separate agreement and are outside the public reference.
- [Standard archival ingestion](https://developers.familysearch.org/main/docs/standard-ingest-procedure) uses vendor-provisioned AWS credentials and a separate transfer workflow, rather than the account API. It is outside this connector.
- OAuth token creation belongs to connection setup. Username/password grants, service-account grants, identity-token exchange, and restricted refresh-token access are not exposed as callable functions.
- FamilySearch app approval and account permissions still apply to every operation. A published endpoint does not guarantee that a particular app key may use it.
- User-tree selection changes the active tree for the FamilySearch session. Avoid concurrent tree switching; specify a tree in request bodies when the API supports it. Memories can be public even when contributed to a private user tree; review [User Trees guidance](https://developers.familysearch.org/main/docs/uploading-a-user-tree) before uploading.
- JSON responses are bounded by Houston's runtime limits. Uploads and downloads use session files. Redirect responses preserve their location for inspection; credentials are never forwarded to arbitrary hosts.
- Memory creation supports raw uploads and single-file multipart uploads, including MP3/M4A audio and BMP/TIFF images. Multi-file `multipart/mixed` batches require separate calls. Artifact replacement supports the documented plain-text story format.

The provider's OpenAPI documents carry an Apache 2.0 license. `catalog.luau` adapts their routes and parameter descriptions; each record links to its source. The preferred-parent routes correct a duplicated segment in the published reference using FamilySearch's corresponding examples. The official tree symbol is extracted from the logo served by the [FamilySearch developer portal](https://developers.familysearch.org/), preserving its original paths and colors in a square viewBox.

Validation uses the real Houston manifest, Luau analyzer, runtime, and mocked HTTP/file fixtures. Live OAuth and a provider-confirmed disposable write require an approved app key, registered callback, and test account; synthetic fixtures do not prove provider approval or live account compatibility.
