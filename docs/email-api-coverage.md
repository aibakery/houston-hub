# Email connector API coverage audit

Checked against public official documentation on 2026-10-24 and the current checkout before this task's changes. No account credentials or live mailbox data were used. This is an exhaustive method inventory of the published Gmail Discovery surface, the Resend OpenAPI surface plus supplemental reference pages, and Fastmail's publicly documented JMAP mail/core/contacts/masked-email surface. It does not imply that private, undocumented Fastmail web-app APIs or every optional IMAP extension is available to external clients.

Research snapshots were saved only in temporary scratch storage, not committed. The method appendices and official links below are self-contained. Official document revision/publication metadata may differ from the audit date; no private or account-specific capability discovery was performed.

There are four email connectors in this checkout: Fastmail, Gmail, IMAP, Resend. No standalone Outlook, SMTP, Exchange, Mailgun, SendGrid, or Postmark connector was found.

This change adds Fastmail `markRead(ids)` and `markUnread(ids)` using batched per-key patches and confirms existing Gmail/IMAP read-state mutations with tests. All other coverage below describes the inspected baseline and outstanding omissions; no live account mutation or deployment is claimed.

## Read/unread conclusion

- Fastmail supports read state through JMAP `Email/set`: patch `keywords/$seen` to `true` for read or JSON `null` for unread. The baseline exposed keyword state when reading but had no mutation operation; this change adds markRead/markUnread. Use a patch, not whole-keyword-map replacement, to preserve flags and drafts. Mailbox `myRights.maySetSeen` and token permissions can restrict writes. [RFC 8621 metadata](https://www.rfc-editor.org/rfc/rfc8621.html#section-4.1.1), [Email/set](https://www.rfc-editor.org/rfc/rfc8621.html#section-4.6), [patch semantics](https://www.rfc-editor.org/rfc/rfc8620.html#section-5.3).
- Gmail already supports it: `modifyMessage({id, removeLabelIds={'UNREAD'}})` marks read; add `UNREAD` for unread. `batchModifyMessages` and `modifyThread` also work. [Gmail modify](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/modify).
- IMAP already supports it: `setFlags({ids, add={'\\Seen'}})` marks read; remove that flag for unread. Reading uses PEEK semantics and should not implicitly mark mail read. [IMAP STORE](https://www.rfc-editor.org/rfc/rfc9051.html#section-6.4.6).
- Resend's ordinary transactional-email resources are not a user mailbox. However, its separately documented Inboxes API does support thread read/unread via `PATCH /inboxes/{inbox_id}/threads/{thread_id}` with `{read:true/false}`. The connector exposes all 29 Inboxes operations since 2026-10-25, so `updateThread({inbox_id, thread_id, read})` marks a thread read or unread. Account availability was not live-tested. [Resend thread update](https://resend.com/docs/api-reference/inboxes/update-thread).

## Fastmail: every public JMAP mail/core method

All JMAP data methods POST to the session-discovered `apiUrl`. Methods normally require `accountId`; standard get uses `ids?` and `properties?`, changes uses `sinceState`/`maxChanges?`, query uses `filter?`/`sort?`/`position?`/`anchor?`/`anchorOffset?`/`limit?`/`calculateTotal?`, queryChanges uses `sinceQueryState` plus query options, and set uses `ifInState?`/`create?`/`update?`/`destroy?`. The linked RFC8620/8621 documents define the full field contracts. MAIL denotes `urn:ietf:params:jmap:mail`; SUBMISSION denotes `urn:ietf:params:jmap:submission`; CORE is always needed. Mutable methods require writable token, connector access, and server/account permissions.

| Method / transport operation | Coverage before this task | What is still missing | Scope / official reference |
|---|---|---|---|
| GET Session | Internal discovery; getProfile returns limited profile | Account selection/shared accounts; raw capabilities and limits; full account/session metadata | CORE; [session](https://www.rfc-editor.org/rfc/rfc8620.html#section-2) |
| Core/echo | Missing | Diagnostic echo | CORE; [echo](https://www.rfc-editor.org/rfc/rfc8620.html#section-4) |
| Mailbox/get | listFolders/listMailFolders | Selecting IDs/properties; subscription/sort order/thread counts/rights metadata | MAIL; [get](https://www.rfc-editor.org/rfc/rfc8621.html#section-2.1) |
| Mailbox/changes | Missing | Incremental folder/count synchronization | MAIL; [changes](https://www.rfc-editor.org/rfc/rfc8621.html#section-2.2) |
| Mailbox/query | Missing | Server-side folder filtering/sorting/pagination | MAIL; [query](https://www.rfc-editor.org/rfc/rfc8621.html#section-2.3) |
| Mailbox/queryChanges | Missing | Incremental folder query updates | MAIL; [queryChanges](https://www.rfc-editor.org/rfc/rfc8621.html#section-2.4) |
| Mailbox/set | createFolder(name,parent) only | Rename, reparent, sort order, subscription, role changes where allowed, deletion; state precondition; removeEmails option on folder destruction | MAIL; [set](https://www.rfc-editor.org/rfc/rfc8621.html#section-2.5) |
| Thread/get | getThread | Arbitrary bulk thread IDs/properties; preserving complete native state/notFound result | MAIL; [get](https://www.rfc-editor.org/rfc/rfc8621.html#section-3.1) |
| Thread/changes | Missing | Incremental thread synchronization | MAIL; [changes](https://www.rfc-editor.org/rfc/rfc8621.html#section-3.2) |
| Email/get | getMessage/getMessages with fixed properties and decoded body | Raw MIME blob ID/download, caller-selected fields, full body tree/parts, separate text+HTML, full native metadata, body fetch options | MAIL; [get](https://www.rfc-editor.org/rfc/rfc8621.html#section-4.2) |
| Email/changes | Missing | Incremental message synchronization | MAIL; [changes](https://www.rfc-editor.org/rfc/rfc8621.html#section-4.3) |
| Email/query | listMessages/listThreads limited filters; newest first; offset cursor | Advanced filters, arbitrary boolean logic, keyword/read/star/attachment/size searches, custom sort, anchor pagination, exposed query state | MAIL; [query](https://www.rfc-editor.org/rfc/rfc8621.html#section-4.4) |
| Email/queryChanges | Missing | Incremental search result synchronization | MAIL; [queryChanges](https://www.rfc-editor.org/rfc/rfc8621.html#section-4.5) |
| Email/set | Move/archive/trash/destroy; internal draft creation for sending | Read/unread is addressed by this change; flagged/answered/arbitrary keywords remain missing, add/remove mailbox memberships while retaining others, standalone drafts, HTML/inline MIME parts/custom headers, conditionally guarded writes | MAIL; [set](https://www.rfc-editor.org/rfc/rfc8621.html#section-4.6) |
| Email/copy | Missing | Cross-account copy, optionally destroy original; choose destination folders/keywords | MAIL; [copy](https://www.rfc-editor.org/rfc/rfc8621.html#section-4.7) |
| Email/import | Missing | Import uploaded raw RFC5322 messages with mailbox/keyword/date metadata | MAIL; [import](https://www.rfc-editor.org/rfc/rfc8621.html#section-4.8) |
| Email/parse | Missing | Parse uploaded/existing MIME blobs without importing | MAIL; [parse](https://www.rfc-editor.org/rfc/rfc8621.html#section-4.9) |
| SearchSnippet/get | Missing | Search-specific highlighted subject/body snippets | MAIL; [snippets](https://www.rfc-editor.org/rfc/rfc8621.html#section-5.1) |
| Identity/get | listIdentities; listAliases merges identities | Selecting IDs/properties and native state; listIdentities already returns full upstream objects despite narrow type annotation | SUBMISSION; [get](https://www.rfc-editor.org/rfc/rfc8621.html#section-6.1) |
| Identity/changes | Missing | Incremental identity synchronization | SUBMISSION; [changes](https://www.rfc-editor.org/rfc/rfc8621.html#section-6.2) |
| Identity/set | Missing | Create/update/delete identities where server permits; display names, reply-to/Bcc defaults, signatures | SUBMISSION; [set](https://www.rfc-editor.org/rfc/rfc8621.html#section-6.3) |
| EmailSubmission/get | Missing | Submission state, undo state, per-recipient delivery feedback, DSN/MDN references | SUBMISSION; [get](https://www.rfc-editor.org/rfc/rfc8621.html#section-7.1) |
| EmailSubmission/changes | Missing | Incremental submission synchronization | SUBMISSION; [changes](https://www.rfc-editor.org/rfc/rfc8621.html#section-7.2) |
| EmailSubmission/query | Missing | Search/list submissions by message, thread, identity, undo state, date | SUBMISSION; [query](https://www.rfc-editor.org/rfc/rfc8621.html#section-7.3) |
| EmailSubmission/queryChanges | Missing | Incremental submission search updates | SUBMISSION; [queryChanges](https://www.rfc-editor.org/rfc/rfc8621.html#section-7.4) |
| EmailSubmission/set | sendMessage/replyMessage immediate creation; sent-folder update | Send existing draft/message, custom SMTP envelope/parameters, delayed sending if server advertises support, cancel pending submission, delete submission history | SUBMISSION; [set](https://www.rfc-editor.org/rfc/rfc8621.html#section-7.5) |
| VacationResponse/get | Missing | Read auto-responder configuration | vacationresponse; [get](https://www.rfc-editor.org/rfc/rfc8621.html#section-8.1) |
| VacationResponse/set | Missing | Enable/disable and configure dates, subject, text and HTML auto-replies | vacationresponse; [set](https://www.rfc-editor.org/rfc/rfc8621.html#section-8.2) |
| HTTP blob upload | Internal attachment upload only | Standalone upload for import/parse/reuse | CORE + accessible account; [upload](https://www.rfc-editor.org/rfc/rfc8620.html#section-6.1) |
| HTTP blob download | Attachment downloads only | Whole-message .eml; arbitrary accessible blobs; blob reuse workflows | CORE + accessible account; [download](https://www.rfc-editor.org/rfc/rfc8620.html#section-6.2) |
| Blob/copy | Missing | Copy binary blobs between accounts | CORE; [copy](https://www.rfc-editor.org/rfc/rfc8620.html#section-6.3) |
| PushSubscription/get | Missing | List registered notification subscriptions | CORE; [get](https://www.rfc-editor.org/rfc/rfc8620.html#section-7.2.1) |
| PushSubscription/set | Missing | Register/update/delete push subscriptions | CORE; [set](https://www.rfc-editor.org/rfc/rfc8620.html#section-7.2.2) |
| EventSource event stream | Missing | Real-time state notifications | CORE; [event stream](https://www.rfc-editor.org/rfc/rfc8620.html#section-7.3) |

### Fastmail advanced query gaps, enumerated

Current exposed filters are `from`, `to`, `subject`, `text`, `alias`/`aliases` (matches From/To/Cc/Bcc), `folder`/`folders`, `after`, `before`, `includeSpamTrash`. Every supplied term combines with AND; an alias internally combines its address fields with OR. Query sort is fixed to receivedAt descending. Thread collapsing exists through listThreads.

Missing standard Email/query filters: `inMailboxOtherThan`, `minSize`, `maxSize`, `allInThreadHaveKeyword`, `someInThreadHaveKeyword`, `noneInThreadHaveKeyword`, `hasKeyword`, `notKeyword`, `hasAttachment`, dedicated `cc`, `bcc`, `body`, `header`, arbitrary AND/OR/NOT composition. These include finding unread mail (`notKeyword='$seen'`), stars (`hasKeyword='$flagged'`) and attachment-only searches. Missing query controls: ascending order, alternative advertised sort fields (size, from, to, subject, sentAt, keyword/thread-keyword comparators), anchor/anchorOffset, caller-controlled calculateTotal, queryState/canCalculateChanges exposure. Optional sorts depend on session mail capability. [Filtering/sorting](https://www.rfc-editor.org/rfc/rfc8621.html#section-4.4).

### Fastmail body, draft, mailbox, and submission nuance

- Drafts can already be found by the drafts folder and read with normal message reads, moved or permanently destroyed. Missing is a standalone draft creation/update/save/send lifecycle. In JMAP message headers/body are immutable after creation; editing a draft generally means creating replacement content and destroying the old draft, not mutating its text in place.
- Current move overwrites the entire mailboxIds set. This is a move, but does not expose JMAP's ability to add/remove individual labels/folders while preserving other memberships. There is no dedicated untrash/spam action, but moveMessages to inbox/junk can perform the corresponding folder change; do not report those as wholly absent capabilities.
- Current replyMessage sends a reply but does not set the original's `$answered`; generic keyword mutation could fix that workflow. Sending accepts text and file attachments but has no HTML argument, inline-content IDs, caller-supplied MIME tree, raw MIME, custom headers, or embedded original-email attachment.
- Email/get could expose all metadata (including blobId, size, sender, inReplyTo, references, full bodyStructure/part fields and parsed header forms); current fixed properties/flattening omit or simplify these. Current headers themselves are already returned.
- Submission scheduling is conditional on server `maxDelayedSend`; cancellation only works before a pending send completes. Delivery/MDN data is optional and may not be available for every recipient. Identity creation cannot manufacture an unverified sendable address; server authorization applies.

### Fastmail extensions and non-mail APIs

Fastmail explicitly documents these additions in [its developer page](https://www.fastmail.com/dev/):

| Surface | Entire method set missing or partial | Notes |
|---|---|---|
| Masked Email | MaskedEmail/get partial via listAliases; MaskedEmail/set entirely missing | Need create addresses, change state (pending/enabled/disabled/deleted), edit description/domain/url, destroy where supported. `emailPrefix` is create-only. Existing wrapper omits url/createdAt/createdBy and native state selection. Scope `https://www.fastmail.com/dev/maskedemail`; server enforces creation rate limits. |
| Address books | AddressBook/get, AddressBook/changes, AddressBook/set all missing | JMAP contacts scope; rights govern creation/deletion. |
| Contact cards | ContactCard/get, ContactCard/changes, ContactCard/query, ContactCard/queryChanges, ContactCard/set, ContactCard/copy all missing | Contacts/group memberships and JSContact fields, searches/sync/copy all absent. [RFC9610](https://www.rfc-editor.org/rfc/rfc9610.html). |
| OAuth login | Authorization-code/refresh flow missing | Manual API token only; Fastmail registers OAuth clients by contacting its developers. Existing access token scope may restrict any above methods. |
| CalDAV calendars | All calendar discovery/read/create/update/delete/event querying/synchronization absent | Official developer page still says public JMAP calendar access will open when specification finalized. Do not promise JMAP calendar methods from internal Fastmail UI behavior. CalDAV is a separate protocol. |
| CardDAV contacts | All CardDAV operations absent | JMAP contacts is already a public alternative; supporting both is not necessary for equivalent contact features. |
| WebDAV files | All file listing/read/upload/copy/move/delete/property operations absent | Separate protocol and credential setup. |
| IMAP/POP/SMTP access | Not exposed by this connector | IMAP is available through the separate generic connector. JMAP already covers mail access/submission; additional protocols are not automatically additional product features. |

Other published JMAP extensions exist (quotas, Sieve rules, sharing/principals, advanced blob access, newer push mechanisms). Fastmail's public developer page does not establish which of these are enabled for third-party tokens. Mark these **provider support unverified**, not confirmed connector omissions: RFC9425 quota methods; RFC9661 SieveScript methods; RFC9670 sharing/principal methods and rights management; RFC9404 advanced blob methods; RFC9749 VAPID push extension. Likewise Fastmail snooze, colored flags, private memos, and administrative domain/user/ordinary alias provisioning must not be presented as documented public JMAP capabilities without official evidence or a granted session capability. Generic keyword support does not automatically implement such private UI semantics.

### Fastmail transport/auth constraints

The connector pins the primary mail account; all shared/secondary-account selection is absent. Discovery uses `https://api.fastmail.com/jmap/session`, then session API/upload/download URLs. Manifest allows api.fastmail.com, regional *.api.fastmail.com, jmap.fastmail.com and fastmailusercontent.com download hosts. HTTP JSON API, file upload/download, bearer token. IDs are opaque; don't substitute RFC Message-ID headers. Server advertises get/set size, concurrent request, upload and mail limits; current batching hardcodes 50. HTTP errors plus JMAP method errors and per-object set errors must all be handled; partial batches may already have applied. Rate limiting is capability/server/account specific; no fixed global requests/second guarantee was found. [JMAP limits](https://www.rfc-editor.org/rfc/rfc8620.html#section-2).

API tokens need a plan above Basic. Email scope permits changes; the Read-only token checkbox prevents them; Email submission adds sending; Masked Email and Contacts need separate scopes. Existing user API-token restrictions cannot be inferred from manual credentials. [Fastmail token setup](https://www.fastmail.help/hc/en-us/articles/5254602856719-API-tokens). Vacation response has a documented OAuth scope; availability under the selected manual token should be established from session capabilities before implementing it.

## Gmail: all omissions

The retrieved official Discovery document contains **79 methods**, of which the connector reaches **27**, leaving **52 unexposed methods**. This is a method count, not 52 distinct user features: labels.update PUT duplicates the label-edit feature already supported with labels.patch. The Gmail appendix below lists every method, path, accepted scopes, parameter names, request schema and official link; the linked official Discovery document supplies complete request/response schemas and field constraints.

| Area | Missing methods/features | Permission/availability |
|---|---|---|
| Permanent deletion | messages.delete, messages.batchDelete, threads.delete | Requires full `https://mail.google.com/`; current gmail.modify intentionally cannot do this. Trash/untrash exists. |
| Import/archive ingestion | messages.import, messages.insert | Current gmail.modify suffices; supports uploaded raw RFC5322 messages, insertion labels/dates and import spam/calendar/deleted behavior. |
| Notifications | users.watch, users.stop | Existing read scope suffices, but requires Cloud Pub/Sub project/topic permission and periodic renewal. Connector has listHistory already. |
| Label full replacement | labels.update | PUT absent; PATCH updateLabel already supports name/color/visibility changes, so low-value duplication. |
| User settings reads | getAutoForwarding, getImap, getLanguage, getPop, getVacation | Existing gmail.readonly/modify suffices. |
| User settings writes | updateAutoForwarding, updateImap, updateLanguage, updatePop, updateVacation | Basic settings scope for IMAP/language/POP/vacation; sharing scope and admin delegation for auto-forwarding. |
| Filters/rules | settings.filters list/get/create/delete | Reads accept existing scope; create/delete need gmail.settings.basic. |
| Forwarding addresses | settings.forwardingAddresses list/get/create/delete | Reads accept existing scopes; mutations need gmail.settings.sharing and delegated service account. |
| Send-as settings | settings.sendAs get/create/patch/update/delete/verify | listSendAs already present. Reads accept existing scope; primary identity signature/basic settings can use settings.basic. New/custom aliases and sensitive operations require Workspace delegated service account; updating non-primary addresses is restricted. |
| Delegates | settings.delegates list/get/create/delete | All require service account with domain-wide delegation; not the connector's normal user OAuth flow. |
| Hosted S/MIME | settings.sendAs.smimeInfo list/get/insert/delete/setDefault | Eligible Workspace account/admin configuration; writes require basic/sharing scope. |
| Client-side encryption identities | settings.cse.identities list/get/create/patch/delete | CSE-enabled Workspace configuration; admin delegation or eligible user hardware-key setup. |
| Client-side encryption keypairs | settings.cse.keypairs list/get/create/enable/disable/obliterate | Same CSE requirements; writes need settings.basic/sharing. |

Sources: [complete REST reference](https://developers.google.com/workspace/gmail/api/reference/rest), [official Discovery JSON](https://gmail.googleapis.com/$discovery/rest?version=v1), [scopes](https://developers.google.com/workspace/gmail/api/auth/scopes), [push](https://developers.google.com/workspace/gmail/api/guides/push), [identity/signature guide](https://developers.google.com/workspace/gmail/api/guides/alias_and_signature_settings).

### Gmail gaps inside methods already offered

- No raw RFC5322 `.eml` retrieval (`format=raw` explicitly rejected), full MIME-tree passthrough, or caller-selected Google response fields. Message read flattens the payload and returns one preferred body; both HTML and text alternatives are not separately exposed. The newly present native `classificationLabelValues` field is dropped by the connector's fixed projection.
- No raw MIME send/draft upload, custom headers, caller-supplied multipart tree, inline attachment content IDs, upload resumability, or large-message send support. Existing send/draft composer caps whole messages around 8 MiB (about 5 MiB attachments); Gmail's API supports larger media uploads. It takes inReplyTo for threading but no arbitrary threadId/new raw-message metadata. Existing sendDraft body passthrough may accept the provider's native replacement message, but this is not a documented ergonomic raw-send API.
- Classification-label mutation fields (`addClassificationLabels`, `removeClassificationLabelIds`) can pass through generic modifyMessage/batchModifyMessages body forwarding, but have no documented help or behavioral coverage. Classification-label readback (`classificationLabelValues`) is dropped by normalized message reads. Google's newer method pages also list a restricted administrative modification scope requiring delegated access; this connector does not request it. These are partial field-level gaps, not missing modify endpoints. [Modify reference](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/modify).
- Native send/draft Message metadata such as initial labelIds/classificationLabelValues cannot be specified through composed create/update/send because the composer rejects unknown keys. Provider restrictions still govern which metadata is writable per method.
- The REST `/batch/gmail/v1` transport is not exposed; getMessages performs bounded concurrent calls. This is an efficiency/transport omission, not a missing mail feature. Global partial-response (`fields`) and quota-project/user request controls are not exposed.
- Existing generic label mutations already cover read/unread, star/unstar, important/unimportant, inbox archive and spam-label changes; there is no need to count each as absent merely because it lacks a dedicated helper.
- Contacts, Calendar, Drive attachments and Postmaster Tools are separate Google APIs, not missing Gmail v1 methods. The connector does not claim to wrap every Google service. Gmail UI-only snooze/scheduled-send configuration is not part of the Gmail v1 Discovery surface.

OAuth is currently publisher-client authorization code + PKCE, mailbox `me`, gmail.readonly for read-only and gmail.modify for read/write. No service-account or domain-wide-delegation auth. Pagination uses pageToken/nextPageToken; listMessages/listThreads cap at 500 and batchModify supports up to 1000 IDs. HTTP errors expose Google's error envelope/reason; quota units vary by method. API host gmail.googleapis.com, upload prefix /upload/gmail/v1. Downloads use messages.attachments.get JSON base64url streaming. [Quotas](https://developers.google.com/workspace/gmail/api/reference/quota).

## IMAP review

Read/unread/starred/answered/custom keyword mutation already exists via setFlags; folder moves, trash moves, creation, bounded listing/search/read and attachment download also exist. Missing commands must be implemented in Houston's native IMAP runtime, not merely added to connector Luau: `app/internal/connect/imap.go` currently dispatches only list/search/fetch/download/store/move/create.

| IMAP capability | Connector coverage / gap |
|---|---|
| CAPABILITY, LOGIN, SELECT/EXAMINE, LOGOUT, UID mechanics | Internal connection protocol; no raw arbitrary command interface (not needed for ordinary mail functions). |
| LIST | Exposed folder list; no caller-selected LIST patterns, subscriptions or extended return options. |
| CREATE | Exposed folder creation. |
| DELETE / RENAME | Missing folder deletion/rename/reparent. |
| SUBSCRIBE / UNSUBSCRIBE | Missing subscription changes. |
| NAMESPACE / STATUS | No direct namespace or detailed mailbox status/UIDNEXT/UIDVALIDITY API; some counts are returned when supplied with folder listing. |
| APPEND | Missing raw message import/save drafts; draft updates require append/delete workflow. |
| IDLE / NOOP notification loop | No long-lived notification subscription; one connection per call. |
| EXPUNGE / UID EXPUNGE | No explicit permanent-deletion operation. Houston forbids adding Deleted through setFlags (removal is allowed); explicit final expunge is also missing. |
| SEARCH | Limited from/to/cc/subject/text/since/before/unread/flagged. No bcc, arbitrary headers/body-only, sent-date, size, arbitrary keyword/answered/draft/deleted criteria, OR/NOT expressions or server sort/thread extensions. |
| FETCH | Envelope/decoded preferred body/attachment convenience. No raw MIME, arbitrary sections/headers/body structure/full-text alternatives/direct UID metadata API. |
| STORE | Add/remove flags supported; no native replace-all-flags or conditional MODSEQ mutation exposed. |
| COPY | Missing copy while retaining original. MOVE is supported (and can perform trash/archive/junk moves). |
| CLOSE / UNSELECT / ENABLE | Connection internals, not retained session operations. |
| Optional ACL, QUOTA, METADATA, SORT, THREAD, CONDSTORE/QRESYNC, NOTIFY and provider extensions | Not exposed; support depends on each server's advertised capabilities, so there is no universal finite provider feature list. |
| SMTP sending | Not an IMAP capability; requires a separate submission transport/connector. |

Source: [IMAP4rev2 standard](https://www.rfc-editor.org/rfc/rfc9051.html). Generic connector uses verified TLS plus LOGIN/app password, not XOAUTH2. Opaque IDs encode folder/UID validity, and move may produce new IDs. Search returns bounded newest-added paging; fetch and store have explicit batch limits. Server-specific extension/role permissions and mailbox rights determine availability.

## Resend review

The official OpenAPI 1.5.1 contains **142 HTTP operations**, **133 exposed**, **9 missing** (rechecked on 2026-10-25, after adding usage and Inboxes). Every operation is listed in the Resend appendix below; the linked official OpenAPI supplies complete schemas. Connector body fields generally pass through to native API, so undocumented optional body fields are often already callable; query fields and endpoint paths are explicitly enumerated.

All OpenAPI omissions:

- API keys: create, rename/update, revoke/delete (3). Key listing is present. Creation returns a new credential and would require intentional secret handling.
- OAuth grants: list and revoke (2). Connector authentication is manual API key, not OAuth.
- Deprecated audiences: create/list/get/delete (4). Contacts and segments already exist; this is legacy redundancy.

Supplemental official documentation outside the OpenAPI adds these unexposed surfaces:

- GET /segments/metrics: contact/subscription counts optionally grouped/scoped by segment. Explicit private beta with potential shape changes. [Docs](https://resend.com/docs/api-reference/segments/get-segment-metrics).
- OAuth client dynamic registration, authorization-code + PKCE authorization, token exchange/refresh and refresh-token revocation. These belong in authentication infrastructure, not ordinary credential-returning connector exports. [Registration](https://resend.com/docs/api-reference/oauth/register), [authorization](https://resend.com/docs/api-reference/oauth/authorize), [token](https://resend.com/docs/api-reference/oauth/token), [revocation](https://resend.com/docs/api-reference/oauth/revoke).

Resend sends, batches, templates, domains/verification/claims, contacts/imports/properties/segments/topics, broadcasts/metrics, events/automations, suppressions, webhook management/replay, request logs, account usage and Inboxes (inboxes, agent settings, labels, threads and their search, thread emails with reply and forward, and drafts) are represented. Attachment downloads can write session files. Signed raw received-message links are returned through getReceivedEmail, but there is no dedicated raw .eml-to-session-file helper. Lists use bounded limit/after/before pagination. Token permission (full access vs sending-only, domain restriction), plan, and feature rollout govern methods; read-only Houston access also hides writes and some reads that reveal secrets. API api.resend.com, plus signed download storage hosts configured in the manifest. Header Idempotency-Key is exposed for sends, batches, inbox replies and forwards, and draft creation and sending. [Official OpenAPI](https://github.com/resend/resend-openapi), [reference](https://resend.com/docs/api-reference/introduction).

## Implementation priorities suggested by audit

1. Fix Fastmail read/unread and expose keyword mutation while preserving all unrelated flags; add unread/flagged/keyword search so state changes are discoverable and verifiable.
2. Preserve Gmail and IMAP's existing working label/flag operations; improve explicit discoverability/tests rather than adding many redundant wrappers.
3. Fastmail next useful work: standalone drafts + HTML, label membership mutation, folder edits/deletion, masked-email management, vacation responder, raw message import/export, and incremental sync.
4. Gmail next useful work: settings/filter reads under current scopes, opt-in basic settings/filter writes with reauthorization, raw MIME/import/export and large uploads. Keep destructive full-mail scope and administrative delegated-account setup separate.
5. Resend next useful work: scoped credential handling for keys/OAuth; segment metrics remain beta.

## Appendix: Gmail API v1 exhaustive method audit

Official Discovery revision: 20261019 ; checked 2026-10-24. IDs/path parameter names below are native provider names. All connector methods address users/me; IDs are opaque. Query fields below exclude standard global Google request fields. The [official Discovery document](https://gmail.googleapis.com/$discovery/rest?version=v1) contains full native schemas, bounds, response types, body and pagination fields.

| Method | HTTP path | Connector coverage | Accepted scopes (alternatives) | Parameters | Request schema | Official reference |
|---|---|---|---|---|---|---|
| `gmail.users.drafts.create` | `POST gmail/v1/users/{userId}/drafts` | createDraft (composed MIME only) | https://mail.google.com/, gmail.addons.current.action.compose, gmail.compose, gmail.modify | userId* | Draft | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.drafts/create) |
| `gmail.users.drafts.delete` | `DELETE gmail/v1/users/{userId}/drafts/{id}` | deleteDraft | https://mail.google.com/, gmail.addons.current.action.compose, gmail.compose, gmail.modify | id*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.drafts/delete) |
| `gmail.users.drafts.get` | `GET gmail/v1/users/{userId}/drafts/{id}` | getDraft | https://mail.google.com/, gmail.compose, gmail.modify, gmail.readonly | format, id*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.drafts/get) |
| `gmail.users.drafts.list` | `GET gmail/v1/users/{userId}/drafts` | listDrafts | https://mail.google.com/, gmail.compose, gmail.modify, gmail.readonly | includeSpamTrash, maxResults, pageToken, q, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.drafts/list) |
| `gmail.users.drafts.send` | `POST gmail/v1/users/{userId}/drafts/send` | sendDraft | https://mail.google.com/, gmail.addons.current.action.compose, gmail.compose, gmail.modify | userId* | Draft | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.drafts/send) |
| `gmail.users.drafts.update` | `PUT gmail/v1/users/{userId}/drafts/{id}` | updateDraft (composed MIME only) | https://mail.google.com/, gmail.addons.current.action.compose, gmail.compose, gmail.modify | id*, userId* | Draft | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.drafts/update) |
| `gmail.users.getProfile` | `GET gmail/v1/users/{userId}/profile` | getProfile | https://mail.google.com/, gmail.compose, gmail.metadata, gmail.modify, gmail.readonly | userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users/getProfile) |
| `gmail.users.history.list` | `GET gmail/v1/users/{userId}/history` | listHistory | https://mail.google.com/, gmail.metadata, gmail.modify, gmail.readonly | historyTypes, labelId, maxResults, pageToken, startHistoryId, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.history/list) |
| `gmail.users.labels.create` | `POST gmail/v1/users/{userId}/labels` | createLabel | https://mail.google.com/, gmail.labels, gmail.modify | userId* | Label | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.labels/create) |
| `gmail.users.labels.delete` | `DELETE gmail/v1/users/{userId}/labels/{id}` | deleteLabel | https://mail.google.com/, gmail.labels, gmail.modify | id*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.labels/delete) |
| `gmail.users.labels.get` | `GET gmail/v1/users/{userId}/labels/{id}` | getLabel | https://mail.google.com/, gmail.labels, gmail.metadata, gmail.modify, gmail.readonly | id*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.labels/get) |
| `gmail.users.labels.list` | `GET gmail/v1/users/{userId}/labels` | listLabels | https://mail.google.com/, gmail.labels, gmail.metadata, gmail.modify, gmail.readonly | userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.labels/list) |
| `gmail.users.labels.patch` | `PATCH gmail/v1/users/{userId}/labels/{id}` | updateLabel | https://mail.google.com/, gmail.labels, gmail.modify | id*, userId* | Label | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.labels/patch) |
| `gmail.users.labels.update` | `PUT gmail/v1/users/{userId}/labels/{id}` | MISSING | https://mail.google.com/, gmail.labels, gmail.modify | id*, userId* | Label | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.labels/update) |
| `gmail.users.messages.attachments.get` | `GET gmail/v1/users/{userId}/messages/{messageId}/attachments/{id}` | getAttachment | https://mail.google.com/, gmail.addons.current.message.action, gmail.addons.current.message.readonly, gmail.modify, gmail.readonly | id*, messageId*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages.attachments/get) |
| `gmail.users.messages.batchDelete` | `POST gmail/v1/users/{userId}/messages/batchDelete` | MISSING | https://mail.google.com/ | userId* | BatchDeleteMessagesRequest | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/batchDelete) |
| `gmail.users.messages.batchModify` | `POST gmail/v1/users/{userId}/messages/batchModify` | batchModifyMessages | https://mail.google.com/, gmail.modify | userId* | BatchModifyMessagesRequest | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/batchModify) |
| `gmail.users.messages.delete` | `DELETE gmail/v1/users/{userId}/messages/{id}` | MISSING | https://mail.google.com/ | id*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/delete) |
| `gmail.users.messages.get` | `GET gmail/v1/users/{userId}/messages/{id}` | getMessage/getMessages (decoded, no raw MIME) | https://mail.google.com/, gmail.addons.current.message.action, gmail.addons.current.message.metadata, gmail.addons.current.message.readonly, gmail.metadata, gmail.modify, gmail.readonly | format, id*, metadataHeaders, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/get) |
| `gmail.users.messages.import` | `POST gmail/v1/users/{userId}/messages/import` | MISSING | https://mail.google.com/, gmail.insert, gmail.modify | deleted, internalDateSource, neverMarkSpam, processForCalendar, userId* | Message | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/import) |
| `gmail.users.messages.insert` | `POST gmail/v1/users/{userId}/messages` | MISSING | https://mail.google.com/, gmail.insert, gmail.modify | deleted, internalDateSource, userId* | Message | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/insert) |
| `gmail.users.messages.list` | `GET gmail/v1/users/{userId}/messages` | listMessages | https://mail.google.com/, gmail.metadata, gmail.modify, gmail.readonly | includeSpamTrash, labelIds, maxResults, pageToken, q, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/list) |
| `gmail.users.messages.modify` | `POST gmail/v1/users/{userId}/messages/{id}/modify` | modifyMessage | https://mail.google.com/, gmail.modify | id*, userId* | ModifyMessageRequest | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/modify) |
| `gmail.users.messages.send` | `POST gmail/v1/users/{userId}/messages/send` | sendMessage (composed MIME only) | https://mail.google.com/, gmail.addons.current.action.compose, gmail.compose, gmail.modify, gmail.send | userId* | Message | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/send) |
| `gmail.users.messages.trash` | `POST gmail/v1/users/{userId}/messages/{id}/trash` | trashMessage | https://mail.google.com/, gmail.modify | id*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/trash) |
| `gmail.users.messages.untrash` | `POST gmail/v1/users/{userId}/messages/{id}/untrash` | untrashMessage | https://mail.google.com/, gmail.modify | id*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/untrash) |
| `gmail.users.settings.cse.identities.create` | `POST gmail/v1/users/{userId}/settings/cse/identities` | MISSING | gmail.settings.basic, gmail.settings.sharing | userId* | CseIdentity | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.cse.identities/create) |
| `gmail.users.settings.cse.identities.delete` | `DELETE gmail/v1/users/{userId}/settings/cse/identities/{cseEmailAddress}` | MISSING | gmail.settings.basic, gmail.settings.sharing | cseEmailAddress*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.cse.identities/delete) |
| `gmail.users.settings.cse.identities.get` | `GET gmail/v1/users/{userId}/settings/cse/identities/{cseEmailAddress}` | MISSING | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic, gmail.settings.sharing | cseEmailAddress*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.cse.identities/get) |
| `gmail.users.settings.cse.identities.list` | `GET gmail/v1/users/{userId}/settings/cse/identities` | MISSING | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic, gmail.settings.sharing | pageSize, pageToken, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.cse.identities/list) |
| `gmail.users.settings.cse.identities.patch` | `PATCH gmail/v1/users/{userId}/settings/cse/identities/{emailAddress}` | MISSING | gmail.settings.basic, gmail.settings.sharing | emailAddress*, userId* | CseIdentity | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.cse.identities/patch) |
| `gmail.users.settings.cse.keypairs.create` | `POST gmail/v1/users/{userId}/settings/cse/keypairs` | MISSING | gmail.settings.basic, gmail.settings.sharing | chainValidation, userId* | CseKeyPair | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.cse.keypairs/create) |
| `gmail.users.settings.cse.keypairs.disable` | `POST gmail/v1/users/{userId}/settings/cse/keypairs/{keyPairId}:disable` | MISSING | gmail.settings.basic, gmail.settings.sharing | keyPairId*, userId* | DisableCseKeyPairRequest | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.cse.keypairs/disable) |
| `gmail.users.settings.cse.keypairs.enable` | `POST gmail/v1/users/{userId}/settings/cse/keypairs/{keyPairId}:enable` | MISSING | gmail.settings.basic, gmail.settings.sharing | keyPairId*, userId* | EnableCseKeyPairRequest | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.cse.keypairs/enable) |
| `gmail.users.settings.cse.keypairs.get` | `GET gmail/v1/users/{userId}/settings/cse/keypairs/{keyPairId}` | MISSING | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic, gmail.settings.sharing | keyPairId*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.cse.keypairs/get) |
| `gmail.users.settings.cse.keypairs.list` | `GET gmail/v1/users/{userId}/settings/cse/keypairs` | MISSING | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic, gmail.settings.sharing | pageSize, pageToken, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.cse.keypairs/list) |
| `gmail.users.settings.cse.keypairs.obliterate` | `POST gmail/v1/users/{userId}/settings/cse/keypairs/{keyPairId}:obliterate` | MISSING | gmail.settings.basic, gmail.settings.sharing | keyPairId*, userId* | ObliterateCseKeyPairRequest | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.cse.keypairs/obliterate) |
| `gmail.users.settings.delegates.create` | `POST gmail/v1/users/{userId}/settings/delegates` | MISSING | gmail.settings.sharing | userId* | Delegate | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.delegates/create) |
| `gmail.users.settings.delegates.delete` | `DELETE gmail/v1/users/{userId}/settings/delegates/{delegateEmail}` | MISSING | gmail.settings.sharing | delegateEmail*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.delegates/delete) |
| `gmail.users.settings.delegates.get` | `GET gmail/v1/users/{userId}/settings/delegates/{delegateEmail}` | MISSING | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic | delegateEmail*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.delegates/get) |
| `gmail.users.settings.delegates.list` | `GET gmail/v1/users/{userId}/settings/delegates` | MISSING | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic | userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.delegates/list) |
| `gmail.users.settings.filters.create` | `POST gmail/v1/users/{userId}/settings/filters` | MISSING | gmail.settings.basic | userId* | Filter | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.filters/create) |
| `gmail.users.settings.filters.delete` | `DELETE gmail/v1/users/{userId}/settings/filters/{id}` | MISSING | gmail.settings.basic | id*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.filters/delete) |
| `gmail.users.settings.filters.get` | `GET gmail/v1/users/{userId}/settings/filters/{id}` | MISSING | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic | id*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.filters/get) |
| `gmail.users.settings.filters.list` | `GET gmail/v1/users/{userId}/settings/filters` | MISSING | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic | userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.filters/list) |
| `gmail.users.settings.forwardingAddresses.create` | `POST gmail/v1/users/{userId}/settings/forwardingAddresses` | MISSING | gmail.settings.sharing | userId* | ForwardingAddress | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.forwardingAddresses/create) |
| `gmail.users.settings.forwardingAddresses.delete` | `DELETE gmail/v1/users/{userId}/settings/forwardingAddresses/{forwardingEmail}` | MISSING | gmail.settings.sharing | forwardingEmail*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.forwardingAddresses/delete) |
| `gmail.users.settings.forwardingAddresses.get` | `GET gmail/v1/users/{userId}/settings/forwardingAddresses/{forwardingEmail}` | MISSING | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic | forwardingEmail*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.forwardingAddresses/get) |
| `gmail.users.settings.forwardingAddresses.list` | `GET gmail/v1/users/{userId}/settings/forwardingAddresses` | MISSING | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic | userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.forwardingAddresses/list) |
| `gmail.users.settings.getAutoForwarding` | `GET gmail/v1/users/{userId}/settings/autoForwarding` | MISSING | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic | userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings/getAutoForwarding) |
| `gmail.users.settings.getImap` | `GET gmail/v1/users/{userId}/settings/imap` | MISSING | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic | userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings/getImap) |
| `gmail.users.settings.getLanguage` | `GET gmail/v1/users/{userId}/settings/language` | MISSING | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic | userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings/getLanguage) |
| `gmail.users.settings.getPop` | `GET gmail/v1/users/{userId}/settings/pop` | MISSING | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic | userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings/getPop) |
| `gmail.users.settings.getVacation` | `GET gmail/v1/users/{userId}/settings/vacation` | MISSING | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic | userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings/getVacation) |
| `gmail.users.settings.sendAs.create` | `POST gmail/v1/users/{userId}/settings/sendAs` | MISSING | gmail.settings.sharing | userId* | SendAs | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.sendAs/create) |
| `gmail.users.settings.sendAs.delete` | `DELETE gmail/v1/users/{userId}/settings/sendAs/{sendAsEmail}` | MISSING | gmail.settings.sharing | sendAsEmail*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.sendAs/delete) |
| `gmail.users.settings.sendAs.get` | `GET gmail/v1/users/{userId}/settings/sendAs/{sendAsEmail}` | MISSING | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic | sendAsEmail*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.sendAs/get) |
| `gmail.users.settings.sendAs.list` | `GET gmail/v1/users/{userId}/settings/sendAs` | listSendAs | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic | userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.sendAs/list) |
| `gmail.users.settings.sendAs.patch` | `PATCH gmail/v1/users/{userId}/settings/sendAs/{sendAsEmail}` | MISSING | gmail.settings.basic, gmail.settings.sharing | sendAsEmail*, userId* | SendAs | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.sendAs/patch) |
| `gmail.users.settings.sendAs.smimeInfo.delete` | `DELETE gmail/v1/users/{userId}/settings/sendAs/{sendAsEmail}/smimeInfo/{id}` | MISSING | gmail.settings.basic, gmail.settings.sharing | id*, sendAsEmail*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.sendAs.smimeInfo/delete) |
| `gmail.users.settings.sendAs.smimeInfo.get` | `GET gmail/v1/users/{userId}/settings/sendAs/{sendAsEmail}/smimeInfo/{id}` | MISSING | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic, gmail.settings.sharing | id*, sendAsEmail*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.sendAs.smimeInfo/get) |
| `gmail.users.settings.sendAs.smimeInfo.insert` | `POST gmail/v1/users/{userId}/settings/sendAs/{sendAsEmail}/smimeInfo` | MISSING | gmail.settings.basic, gmail.settings.sharing | sendAsEmail*, userId* | SmimeInfo | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.sendAs.smimeInfo/insert) |
| `gmail.users.settings.sendAs.smimeInfo.list` | `GET gmail/v1/users/{userId}/settings/sendAs/{sendAsEmail}/smimeInfo` | MISSING | https://mail.google.com/, gmail.modify, gmail.readonly, gmail.settings.basic, gmail.settings.sharing | sendAsEmail*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.sendAs.smimeInfo/list) |
| `gmail.users.settings.sendAs.smimeInfo.setDefault` | `POST gmail/v1/users/{userId}/settings/sendAs/{sendAsEmail}/smimeInfo/{id}/setDefault` | MISSING | gmail.settings.basic, gmail.settings.sharing | id*, sendAsEmail*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.sendAs.smimeInfo/setDefault) |
| `gmail.users.settings.sendAs.update` | `PUT gmail/v1/users/{userId}/settings/sendAs/{sendAsEmail}` | MISSING | gmail.settings.basic, gmail.settings.sharing | sendAsEmail*, userId* | SendAs | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.sendAs/update) |
| `gmail.users.settings.sendAs.verify` | `POST gmail/v1/users/{userId}/settings/sendAs/{sendAsEmail}/verify` | MISSING | gmail.settings.sharing | sendAsEmail*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings.sendAs/verify) |
| `gmail.users.settings.updateAutoForwarding` | `PUT gmail/v1/users/{userId}/settings/autoForwarding` | MISSING | gmail.settings.sharing | userId* | AutoForwarding | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings/updateAutoForwarding) |
| `gmail.users.settings.updateImap` | `PUT gmail/v1/users/{userId}/settings/imap` | MISSING | gmail.settings.basic | userId* | ImapSettings | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings/updateImap) |
| `gmail.users.settings.updateLanguage` | `PUT gmail/v1/users/{userId}/settings/language` | MISSING | gmail.settings.basic | userId* | LanguageSettings | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings/updateLanguage) |
| `gmail.users.settings.updatePop` | `PUT gmail/v1/users/{userId}/settings/pop` | MISSING | gmail.settings.basic | userId* | PopSettings | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings/updatePop) |
| `gmail.users.settings.updateVacation` | `PUT gmail/v1/users/{userId}/settings/vacation` | MISSING | gmail.settings.basic | userId* | VacationSettings | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.settings/updateVacation) |
| `gmail.users.stop` | `POST gmail/v1/users/{userId}/stop` | MISSING | https://mail.google.com/, gmail.metadata, gmail.modify, gmail.readonly | userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users/stop) |
| `gmail.users.threads.delete` | `DELETE gmail/v1/users/{userId}/threads/{id}` | MISSING | https://mail.google.com/ | id*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.threads/delete) |
| `gmail.users.threads.get` | `GET gmail/v1/users/{userId}/threads/{id}` | getThread | https://mail.google.com/, gmail.addons.current.message.action, gmail.addons.current.message.metadata, gmail.addons.current.message.readonly, gmail.metadata, gmail.modify, gmail.readonly | format, id*, metadataHeaders, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.threads/get) |
| `gmail.users.threads.list` | `GET gmail/v1/users/{userId}/threads` | listThreads | https://mail.google.com/, gmail.metadata, gmail.modify, gmail.readonly | includeSpamTrash, labelIds, maxResults, pageToken, q, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.threads/list) |
| `gmail.users.threads.modify` | `POST gmail/v1/users/{userId}/threads/{id}/modify` | modifyThread | https://mail.google.com/, gmail.modify | id*, userId* | ModifyThreadRequest | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.threads/modify) |
| `gmail.users.threads.trash` | `POST gmail/v1/users/{userId}/threads/{id}/trash` | trashThread | https://mail.google.com/, gmail.modify | id*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.threads/trash) |
| `gmail.users.threads.untrash` | `POST gmail/v1/users/{userId}/threads/{id}/untrash` | untrashThread | https://mail.google.com/, gmail.modify | id*, userId* | — | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.threads/untrash) |
| `gmail.users.watch` | `POST gmail/v1/users/{userId}/watch` | MISSING | https://mail.google.com/, gmail.metadata, gmail.modify, gmail.readonly | userId* | WatchRequest | [docs](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users/watch) |

## Appendix: Resend OpenAPI exhaustive path/method audit

Official OpenAPI version 1.5.1 ; checked 2026-10-24. Complete request schemas, permissions and parameters are in the [official OpenAPI](https://github.com/resend/resend-openapi). Path placeholders normalized only for comparison. Webhook event schemas are not HTTP operations.

| Method/path | Connector coverage | Official operation |
|---|---|---|
| `GET /api-keys` | listApiKeys | api-keys/list |
| `POST /api-keys` | MISSING | api-keys/create |
| `DELETE /api-keys/{api_key_id}` | MISSING | api-keys/remove |
| `PATCH /api-keys/{api_key_id}` | MISSING | api-keys/update |
| `GET /audiences` | MISSING | audiences/list |
| `POST /audiences` | MISSING | audiences/create |
| `DELETE /audiences/{id}` | MISSING | audiences/remove |
| `GET /audiences/{id}` | MISSING | audiences/get |
| `GET /automations` | listAutomations | automations/list |
| `POST /automations` | createAutomation | automations/create |
| `DELETE /automations/{automation_id}` | deleteAutomation | automations/remove |
| `GET /automations/{automation_id}` | getAutomation | automations/get |
| `PATCH /automations/{automation_id}` | updateAutomation | automations/update |
| `POST /automations/{automation_id}/duplicate` | duplicateAutomation | automations/duplicate |
| `GET /automations/{automation_id}/runs` | listAutomationRuns | automations/list-runs |
| `GET /automations/{automation_id}/runs/{run_id}` | getAutomationRun | automations/get-run |
| `POST /automations/{automation_id}/stop` | stopAutomation | automations/stop |
| `GET /broadcasts` | listBroadcasts | broadcasts/list |
| `POST /broadcasts` | createBroadcast | broadcasts/create |
| `DELETE /broadcasts/{id}` | deleteBroadcast | broadcasts/remove |
| `GET /broadcasts/{id}` | getBroadcast | broadcasts/get |
| `PATCH /broadcasts/{id}` | updateBroadcast | broadcasts/update |
| `POST /broadcasts/{id}/cancel` | cancelBroadcast | broadcasts/cancel |
| `GET /broadcasts/{id}/clicked-links` | listBroadcastClickedLinks | broadcasts/list-clicked-links |
| `POST /broadcasts/{id}/duplicate` | duplicateBroadcast | broadcasts/duplicate |
| `GET /broadcasts/{id}/recipients` | listBroadcastRecipients | broadcasts/recipients |
| `POST /broadcasts/{id}/send` | sendBroadcast | broadcasts/send |
| `GET /contact-properties` | listContactProperties | contact-properties/list |
| `POST /contact-properties` | createContactProperty | contact-properties/create |
| `DELETE /contact-properties/{id}` | deleteContactProperty | contact-properties/remove |
| `GET /contact-properties/{id}` | getContactProperty | contact-properties/get |
| `PATCH /contact-properties/{id}` | updateContactProperty | contact-properties/update |
| `GET /contacts` | listContacts | contacts/list |
| `POST /contacts` | createContact | contacts/create |
| `GET /contacts/imports` | listContactImports | contacts/list-imports |
| `POST /contacts/imports` | createContactImport | contacts/create-import |
| `GET /contacts/imports/{id}` | getContactImport | contacts/get-import |
| `GET /contacts/{contact_id}/segments` | listContactSegments | contacts/list-segments |
| `DELETE /contacts/{contact_id}/segments/{segment_id}` | removeContactFromSegment | contacts/remove-segment |
| `POST /contacts/{contact_id}/segments/{segment_id}` | addContactToSegment | contacts/add-segment |
| `GET /contacts/{contact_id}/topics` | listContactTopics | contacts/list-topics |
| `PATCH /contacts/{contact_id}/topics` | updateContactTopics | contacts/update-topics |
| `DELETE /contacts/{id}` | deleteContact | contacts/remove |
| `GET /contacts/{id}` | getContact | contacts/get |
| `PATCH /contacts/{id}` | updateContact | contacts/update |
| `GET /domains` | listDomains | domains/list |
| `POST /domains` | createDomain | domains/create |
| `POST /domains/claim` | claimDomain | domains/create-claim |
| `DELETE /domains/{domain_id}` | deleteDomain | domains/remove |
| `GET /domains/{domain_id}` | getDomain | domains/get |
| `PATCH /domains/{domain_id}` | updateDomain | domains/update |
| `GET /domains/{domain_id}/claim` | getDomainClaim | domains/get-claim |
| `POST /domains/{domain_id}/claim/verify` | verifyDomainClaim | domains/verify-claim |
| `POST /domains/{domain_id}/verify` | verifyDomain | domains/verify |
| `GET /emails` | listEmails | emails/list |
| `POST /emails` | sendEmail | emails/send |
| `POST /emails/batch` | sendBatchEmails | emails/send-batch |
| `GET /emails/metrics` | getEmailMetrics | emails/metrics |
| `GET /emails/receiving` | listReceivedEmails | emails/list-receiving |
| `GET /emails/receiving/{email_id}` | getReceivedEmail | emails/get-receiving |
| `GET /emails/receiving/{email_id}/attachments` | listReceivedEmailAttachments | emails/list-receiving-attachments |
| `GET /emails/receiving/{email_id}/attachments/{attachment_id}` | getReceivedEmailAttachment | emails/get-receiving-attachment |
| `GET /emails/{email_id}` | getEmail | emails/get |
| `PATCH /emails/{email_id}` | updateEmail | emails/update |
| `GET /emails/{email_id}/attachments` | listEmailAttachments | emails/list-attachments |
| `GET /emails/{email_id}/attachments/{attachment_id}` | getEmailAttachment | emails/get-attachment |
| `POST /emails/{email_id}/cancel` | cancelEmail | emails/cancel |
| `POST /emails/{email_id}/share` | shareEmail | emails/share |
| `GET /events` | listEvents | events/list |
| `POST /events` | createEvent | events/create |
| `POST /events/send` | sendEvent | events/send |
| `DELETE /events/{identifier}` | deleteEvent | events/remove |
| `GET /events/{identifier}` | getEvent | events/get |
| `PATCH /events/{identifier}` | updateEvent | events/update |
| `GET /inboxes` | listInboxes | inboxes/list |
| `POST /inboxes` | createInbox | inboxes/create |
| `DELETE /inboxes/{inbox_id}` | deleteInbox | inboxes/remove |
| `GET /inboxes/{inbox_id}` | getInbox | inboxes/get |
| `PATCH /inboxes/{inbox_id}` | updateInbox | inboxes/update |
| `GET /inboxes/{inbox_id}/agent` | getInboxAgent | inboxes/get-agent |
| `PATCH /inboxes/{inbox_id}/agent` | updateInboxAgent | inboxes/update-agent |
| `GET /inboxes/{inbox_id}/drafts` | listDrafts | inboxes/list-drafts |
| `POST /inboxes/{inbox_id}/drafts` | createDraft | inboxes/create-draft |
| `DELETE /inboxes/{inbox_id}/drafts/{draft_id}` | deleteDraft | inboxes/remove-draft |
| `GET /inboxes/{inbox_id}/drafts/{draft_id}` | getDraft | inboxes/get-draft |
| `PATCH /inboxes/{inbox_id}/drafts/{draft_id}` | updateDraft | inboxes/update-draft |
| `POST /inboxes/{inbox_id}/drafts/{draft_id}/send` | sendDraft | inboxes/send-draft |
| `GET /inboxes/{inbox_id}/labels` | listInboxLabels | inboxes/list-labels |
| `POST /inboxes/{inbox_id}/labels` | createInboxLabel | inboxes/create-label |
| `DELETE /inboxes/{inbox_id}/labels/{label_id}` | deleteInboxLabel | inboxes/remove-label |
| `PATCH /inboxes/{inbox_id}/labels/{label_id}` | updateInboxLabel | inboxes/update-label |
| `GET /inboxes/{inbox_id}/threads` | listThreads | inboxes/list-threads |
| `GET /inboxes/{inbox_id}/threads/search` | searchThreads | inboxes/search-threads |
| `DELETE /inboxes/{inbox_id}/threads/{thread_id}` | deleteThread | inboxes/remove-thread |
| `GET /inboxes/{inbox_id}/threads/{thread_id}` | getThread | inboxes/get-thread |
| `PATCH /inboxes/{inbox_id}/threads/{thread_id}` | updateThread | inboxes/update-thread |
| `GET /inboxes/{inbox_id}/threads/{thread_id}/emails` | listThreadEmails | inboxes/list-thread-emails |
| `GET /inboxes/{inbox_id}/threads/{thread_id}/emails/{email_id}` | getThreadEmail | inboxes/get-thread-email |
| `POST /inboxes/{inbox_id}/threads/{thread_id}/emails/{email_id}/forward` | forwardThreadEmail | inboxes/forward-thread-email |
| `POST /inboxes/{inbox_id}/threads/{thread_id}/emails/{email_id}/reply` | replyToThreadEmail | inboxes/reply-thread-email |
| `POST /inboxes/{inbox_id}/threads/{thread_id}/labels` | addThreadLabels | inboxes/add-thread-labels |
| `PUT /inboxes/{inbox_id}/threads/{thread_id}/labels` | setThreadLabels | inboxes/set-thread-labels |
| `DELETE /inboxes/{inbox_id}/threads/{thread_id}/labels/{label_id}` | removeThreadLabel | inboxes/remove-thread-label |
| `GET /logs` | listLogs | logs/list |
| `GET /logs/{log_id}` | getLog | logs/get |
| `GET /oauth/grants` | MISSING | oauth/list-grants |
| `DELETE /oauth/grants/{oauth_grant_id}` | MISSING | oauth/revoke-grant |
| `GET /segments` | listSegments | segments/list |
| `POST /segments` | createSegment | segments/create |
| `DELETE /segments/{id}` | deleteSegment | segments/remove |
| `GET /segments/{id}` | getSegment | segments/get |
| `PATCH /segments/{id}` | updateSegment | segments/update |
| `GET /segments/{id}/contacts` | listSegmentContacts | segments/list-contacts |
| `GET /suppressions` | listSuppressions | suppressions/list |
| `POST /suppressions` | addSuppression | suppressions/add |
| `POST /suppressions/batch/add` | addSuppressions | suppressions/batch-add |
| `POST /suppressions/batch/remove` | removeSuppressions | suppressions/batch-remove |
| `DELETE /suppressions/{suppression}` | removeSuppression | suppressions/remove |
| `GET /suppressions/{suppression}` | getSuppression | suppressions/get |
| `GET /templates` | listTemplates | templates/list |
| `POST /templates` | createTemplate | templates/create |
| `DELETE /templates/{id}` | deleteTemplate | templates/remove |
| `GET /templates/{id}` | getTemplate | templates/get |
| `PATCH /templates/{id}` | updateTemplate | templates/update |
| `POST /templates/{id}/duplicate` | duplicateTemplate | templates/duplicate |
| `POST /templates/{id}/publish` | publishTemplate | templates/publish |
| `GET /topics` | listTopics | topics/list |
| `POST /topics` | createTopic | topics/create |
| `DELETE /topics/{id}` | deleteTopic | topics/remove |
| `GET /topics/{id}` | getTopic | topics/get |
| `PATCH /topics/{id}` | updateTopic | topics/update |
| `GET /usage` | getUsage | usage/get |
| `GET /webhooks` | listWebhooks | webhooks/list |
| `POST /webhooks` | createWebhook | webhooks/create |
| `DELETE /webhooks/{webhook_id}` | deleteWebhook | webhooks/remove |
| `GET /webhooks/{webhook_id}` | getWebhook | webhooks/get |
| `PATCH /webhooks/{webhook_id}` | updateWebhook | webhooks/update |
| `GET /webhooks/{webhook_id}/events` | listWebhookEvents | webhooks/list-events |
| `GET /webhooks/{webhook_id}/events/{event_id}` | getWebhookEvent | webhooks/get-event |
| `GET /webhooks/{webhook_id}/events/{event_id}/attempts` | listWebhookEventAttempts | webhooks/list-event-attempts |
| `POST /webhooks/{webhook_id}/events/{event_id}/replay` | replayWebhookEvent | webhooks/replay-event |
| `POST /webhooks/{webhook_id}/signing-secret/rotate` | rotateWebhookSigningSecret | webhooks/rotate-signing-secret |
