# Provider publishing notes

Provider application setup, release requirements, coverage and icon attribution
for maintained bundles. For the shared publishing workflow, see
[Publish a Hub publication](../AUTHORING.md#publish-a-hub-publication).

## the Google connectors

Register repository `https://github.com/aibakery/houston-hub`, revision `main`, and
the manifest paths `connectors/gmail/houston.json`, `connectors/gcalendar/houston.json`,
`connectors/gdrive/houston.json` and `connectors/gsheets/houston.json`. The bundles use Houston's async HTTP and file
runtime and a publisher-owned OAuth client, so users only choose an access level and
select **Connect with Google**.

In the Google Cloud project that owns Houston's client:

1. Enable the Gmail API, Google Calendar API, Google Drive API and Google Sheets API.
2. Configure the OAuth consent screen (External) with Houston's name, logo, home
   page, privacy policy and authorized domain, and declare the scopes below.
3. Create a **Web application** OAuth client. Add each publication's redirect URI,
   `<Houston public URL>/oauth/connectors/<hub-publication-id>/callback`, to its
   authorized redirect URIs.
4. Enter the client ID and secret in each publication's publisher settings.

One client can serve all four publications, or each publication can have its own
client in a separate project; the bundles work either way.

| Connector | Read-only scopes | Read and write scopes |
| --- | --- | --- |
| Gmail | `gmail.readonly` (restricted) | `gmail.modify` (restricted) |
| Google Calendar | `calendar.readonly` (sensitive) | `calendar.readonly`, `calendar.events` (sensitive) |
| Google Drive | `drive.readonly` (restricted) | `drive` (restricted) |
| Google Sheets | `spreadsheets.readonly` (sensitive) | `spreadsheets` (sensitive) |

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
`www.googleapis.com/calendar/v3`, Drive `www.googleapis.com/drive/v3` and
`/upload/drive/v3`, and Sheets `sheets.googleapis.com/v4/spreadsheets`. Bundles cannot
share files, so the four `connector.lua` files carry the same request layer;
`tools/validate` checks that the copies match.

Google Sheets covers 10 of the 17 `spreadsheets.*` methods in the
[Sheets API v4 discovery document](https://sheets.googleapis.com/$discovery/rest?version=v4),
revision `20261012`, checked on 2026-10-16: spreadsheet metadata, value reads, updates,
appends and clears with their batch forms, spreadsheet creation and the structural
`batchUpdate`. Omitted for now: the `*ByDataFilter` variants and developer metadata,
which select ranges by tags an app attached and whose POST reads need the write scope,
and `sheets.copyTo`, which `batchUpdate`'s `duplicateSheet` covers inside a
spreadsheet. The Sheets scopes cannot list or search files, so callers pass a
spreadsheet ID or URL, or find it through Google Drive. Read-only connections, and
read-only callers of read-write ones, may only GET the three read routes, with
method-override headers removed; writes POST or PUT the listed routes. Writes default
to `valueInputOption=RAW`, so text that looks like a formula stays text unless the
caller asks for `USER_ENTERED`.

Google Sheets' icon is the official product logo served by Google at
[fonts.gstatic.com/s/i/productlogos/sheets_2020q4/v11/192px.svg](https://fonts.gstatic.com/s/i/productlogos/sheets_2020q4/v11/192px.svg),
retrieved 2026-10-16, unchanged. Google owns the mark.

## Notion

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest path `connectors/notion/houston.json`. It requires a Houston deployment
with JSON OAuth token encoding, opaque path parameters and native
`http.multipart`. OAuth client settings belong to each connection, not this publication.

The account-user [Notion setup guide](../connectors/notion/SETUP.md) explains how
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

## IMAP

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest path `connectors/imap/houston.json`. It requires a Houston deployment
with the native `imap` protocol. Each connection supplies its own server,
username and password; the [account setup guide](../connectors/imap/SETUP.md) covers
app passwords and unsupported providers. The connector reads and organizes mail;
sending needs SMTP, which is a different protocol. The envelope icon is drawn for
this bundle, since IMAP is a protocol without an owner's mark.

## Mercury

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest path `connectors/mercury/houston.json`. The bundle uses the existing
manifest v1 and async HTTP/file runtime, including native multipart uploads;
no Mercury client registration or publisher credentials are needed.
The [account setup guide](../connectors/mercury/SETUP.md) covers API tokens and
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

## LinkedIn

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

## WooCommerce

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest path `connectors/woocommerce/houston.json`. It requires a Houston deployment
that renders templated HTTP proxy hosts. No publisher settings or provider app are
needed: each connection enters its store domain and a WooCommerce REST API key, as
the [account setup guide](../connectors/woocommerce/SETUP.md) describes.

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

## Cal.com

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest path `connectors/calcom/houston.json`. The bundle uses the existing
manifest v1 and async HTTP runtime; no publisher settings or provider app are
needed. Each connection enters a Cal.com API key, as the
[account setup guide](../connectors/calcom/SETUP.md) describes.

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

## Calendly

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest path `connectors/calendly/houston.json`. The bundle uses the existing
manifest v1 and async HTTP runtime. Connections use a personal access token or
their own Calendly OAuth app; the [account setup guide](../connectors/calendly/SETUP.md)
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

## Dropbox

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest path `connectors/dropbox/houston.json`. The bundle uses the existing
manifest v1 and async HTTP/file runtime. Standard sign-in uses a publisher-owned
Dropbox app. Connection admins can optionally enable **Use your own Dropbox app**;
the [account setup guide](../connectors/dropbox/SETUP.md) keeps those steps under Advanced.

Create a **Scoped access → Full Dropbox** app in the
[Dropbox App Console](https://www.dropbox.com/developers/apps). Enable
`account_info.read`, `files.metadata.read`, `files.content.read`, `sharing.read`,
`file_requests.read`, `files.content.write`, `sharing.write` and `file_requests.write`.
Register the publication's callback URL shown by Hub, then save its **App key** and
**App secret** as publisher settings. Enable additional users for development;
Dropbox permits up to 500 linked accounts and requires production approval
within two weeks of reaching 50. Standard sign-in remains unavailable until the
publisher credentials are saved; own-app connections remain available independently.

Dropbox's [rate limits](https://docs.dropboxapi.com/dropbox-api/docs/performance)
apply per user/app authorization, so users of one app do not share a single request
budget. Multiple Houston connections for the same Dropbox account and app share
that budget. Concurrent writes can also hit namespace limits. Honor `Retry-After`.
The [developer guide](https://docs.dropboxapi.com/dropbox-api/docs/developer-resources/developer-guide)
requires developers using a DBX Platform wrapper to obtain their own app keys;
confirm Houston's classification with Dropbox before broad public rollout.

This release changes the default OAuth method from a connection-owned client to
the publisher app. Existing connections may need setup again: select the own-app
option to retain their app, or sign in through the publisher app. Authorizations
and refresh tokens cannot transfer between apps. Folder access and callable APIs
are unchanged. Both methods use PKCE and offline access with server-side refresh.

The connector covers 69 user routes of the [Dropbox API v2
specification](https://github.com/dropbox/dropbox-api-spec), checked on 2026-10-16
at revision `3c363a594dafbe0f4646e73352b62a4767540d25`:
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
response, and Houston refuses an authorization that lacks a requested one. Exports
and help also honor known granted scopes; unknown grants retain the configured
access surface. No exposed route needs `files.metadata.write`, so it is no longer
requested. Existing grants may retain that unused scope until reauthorization;
the callable signatures are unchanged. Download
and upload routes send their argument in the `Dropbox-API-Arg` header, which Dropbox
requires to be ASCII: the connector escapes other characters as JSON `\u` escapes.
Required top-level argument types are checked before requests; Dropbox validates
nested values and other route constraints. Downloads await destination opening
before HTTP and close it on request failure. Only the five sharing routes with
void results convert JSON null to `{success=true}`; malformed empty responses fail.
Full team-space traversal with `Dropbox-API-Path-Root` remains unsupported.

Validation uses the current async runtime, including native file and Reader
fixtures for large streamed downloads, open/transport/stream failures, bounded
errors and scope-aware discovery. Before announcing a registered connection,
verify live OAuth authorization and refresh, paging and a disposable upload/download.
These require an account and are not covered by local fixtures.

Dropbox's icon is the existing blue Dropbox mark, unchanged and shared with Houston's
app marks through the central vendor-asset registry. Dropbox owns the mark.

## Resend

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest path `connectors/resend/houston.json`. The bundle uses the existing
manifest v1 and async HTTP/file runtime, including native multipart uploads; no
publisher settings or provider app are needed. Each connection enters a Resend API
key, as the [account setup guide](../connectors/resend/SETUP.md) describes.

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

## Stripe

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest `connectors/stripe/houston.json`. No publisher settings or OAuth app are
needed. The bundle uses the current async HTTP/file runtime without runtime
changes. Connections use their own restricted or secret key; the [setup
guide](../connectors/stripe/SETUP.md) describes permissions and live/test selection.

Coverage was checked on 2026-10-16 against Stripe's [public
OpenAPI](https://github.com/stripe/openapi/blob/cb82ea31b088e117b40b9187a01b08b140f0aeb0/openapi/spec3.json),
version `2026-09-30.endive`. The 69 operations cover account and balance reads,
balance transactions, customers and customer search, products, prices, payment
intents, charges, refunds, subscriptions, invoices and invoice items, payment
methods, payouts, disputes, events, Checkout and billing portal sessions, and
files. These are a selected public API surface, not every Stripe endpoint. Omitted:
API v2, Connect account administration and per-request account selection, OAuth,
API key management, webhook management/receiving, raw card collection, Identity,
Issuing, Treasury, Tax and other product families. Deprecated direct charge
creation/capture is replaced by PaymentIntents. Search beyond customers and
additional nested resource operations are not yet exposed.

Both Lua requests and proxy injection pin `Stripe-Version: 2026-09-30.endive`.
The proxy injects credentials only into explicit routes on `api.stripe.com` and
`files.stripe.com`; POST/DELETE rules require read-write access and all rules
remove account/context and method override headers. Files stream through native
multipart and Reader/File APIs; content downloads use a fixed Stripe Files route,
not a caller URL. Other provider URLs, including invoice PDFs, are returned
unchanged. Read-only JSON responses recursively remove fields named `client_secret`,
`confirmation_secret`, `client_token` and `secret`, including fields inside
metadata, expansions and event payloads. These credentials can authorize payment
or setup outside Houston, so they cannot cross the read-only export boundary.
Other values and read-write responses are preserved. Hosted payment links remain
sensitive. Requests validate generic
form structure, path IDs, paging bounds and unconditional required fields; Stripe
validates resource-specific types and conditional alternatives. Errors are bounded,
include Stripe diagnostic headers, and honor `Stripe-Should-Retry`; no operation
is automatically retried.

There was no Stripe Lua bundle in this catalog, so this introduces a new
registration without migrating existing connection settings. Local runtime fixtures
cover access, form encoding, mutation routes, upstream errors and streamed file
transfers. Live key permissions, sandbox/live behavior and a disposable provider
write remain for the registering user to verify.

Atlas is separate from this payments API. No documented self-service Atlas API
was found in the public spec or [Atlas documentation](https://docs.stripe.com/atlas).
[Incorporation documents](https://docs.stripe.com/atlas/incorporation-documents)
are accessed through the Atlas Dashboard. The official [Pilot Atlas partner
app](https://marketplace.stripe.com/apps/atlas-perks-by-pilot) shows a partner-only
integration and Atlas company-information permission; it does not supply a public
endpoint/authentication contract. Do not substitute Payments Accounts or Files
for Atlas records. A separate Atlas connector requires supported partner access
and documentation, so no placeholder Atlas bundle is published.

The Stripe icon is the existing approved app mark, copied byte-identically from
Houston's `app/internal/web/static/marks/stripe.svg`. Stripe owns the mark.

## Wise

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest `connectors/wise/houston.json`. No publisher settings or OAuth app are
needed, and the bundle uses the current runtime without changes. Each connection
enters its own Wise personal API token and selects **Production**
(`api.wise.com`) or **Sandbox** (`api.wise-sandbox.com`). The environment setting
is the proxy host itself, so a token is only ever sent to the selected Wise
origin; the manifest rejects any other value.

Coverage was checked on 2026-10-16 against Wise's official OpenAPI bundles
(`https://docs.wise.com/_bundle/api-reference/@legacy/index.yaml` and `@latest`,
CalVer `2026Q4`) and the [personal API token
guide](https://docs.wise.com/guides/developer/auth-and-security/personal-api-token).
The 35 operations cover the user and profiles, balances and total funds,
balance statements (JSON and file downloads), receiving account details, the
activity feed, rates, currencies, transfers and receipts, quotes, recipient
requirements and recipients, and batch groups. Writes cover quotes, recipient
creation, transfer requirements, transfer creation, cancellation and funding,
balance creation, closure and movements, and batch groups.

The bundle uses Wise's legacy per-endpoint paths (`/v1`–`/v4`). Wise documents
these as supported and frozen, and its personal-token guides use them; the
`2026Q4` CalVer replacement of account details serves only GB, US and BE.
Moving to a CalVer prefix later changes every route and fixture together.

Deliberate omissions: webhooks (subscriptions deliver account events to an
arbitrary URL and are of little use to agents), cards and card transactions,
the multi-currency-account and delivery-estimate endpoints (the spec marks them
partner-token only), recipient deactivation (likewise), profile and KYC changes,
OAuth, one-time-token/SCA, PIN and JOSE endpoints, and the `twcard.wise.com`
card-secrets host. The proxy denies all of these and the legacy
`api.transferwise.com` host.

Wise documents that personal tokens can fund transfers or batches and fetch
balance statements only for accounts based in the US, Canada, Australia, New Zealand,
Singapore and Malaysia. Elsewhere Wise answers 403 with
`x-2fa-approval-result`; the connector reports that the step must be finished in
the Wise app and marks it not retryable, without echoing the one-time token. The
official spec marks quotes and recipients as partner-token only while the
personal-token guide allows them; the guide was followed. `getQuote`,
`getRecipient` and `refreshAccountRequirements` are tagged partner-token only and
are not named by the guide either, so verify them live; they fail with Wise's
own 401/403 if personal tokens cannot use them. Business payment approvals block
API-created transfers; help and setup state this.

Read-only connections get GET routes only; POST, PATCH, PUT and DELETE routes
require read-write access. Every rule strips method-override headers, though
probes showed Wise's gateway ignores them. Requests validate integer and UUID
path IDs, currency codes, statement formats, documented paging bounds, query enums and
unconditional required fields, and require UUID idempotency keys
(`customerTransactionId`, `X-idempotence-uuid`) for transfers, balances and
balance movements. Errors are bounded, include Wise's error items, `Retry-After`
and `x-trace-id`, and no operation is retried automatically. Only 429s and 5xx
responses to reads or to calls that move no money (quotes and requirement
checks) are marked retryable: Wise says a 5xx does not prove a write failed, so
other writes report them as not retryable. Only a 403 carrying
`x-2fa-approval-result: REJECTED` is reported as an SCA requirement. JSON larger
than the 8 MiB read limit fails with a structured error asking for a narrower
interval or page. Downloads open their session
file only after a successful, non-JSON, non-HTML response, so an error leaves an
existing file untouched; a stream that fails after Wise starts sending the file
can leave it partial. A write answered with an empty 2xx body returns
`{success=true}` instead of an error that could prompt a repeat.

This is a new registration with no existing connections. Local fixtures cover
both access levels, both environments, every route, downloads and error mapping.
A live check with a real token (discovery, help at both access levels, paging,
a sandbox quote, recipient and transfer, and the SCA response outside the exempt
countries) remains for the registering user.

The Wise icon is Wise's own app mark (bright-green flag on a forest-green
circle), referenced from the [wise.com](https://wise.com) homepage at
`https://dq8dwmysp7hk1.cloudfront.net/logos/wise-mark.svg`, retrieved 2026-10-16,
unchanged. Wise owns the mark.

## GitHub

Register repository `https://github.com/aibakery/houston-hub`, revision `main`,
manifest path `connectors/github/houston.json`. The bundle uses the existing
manifest v1 and async HTTP/file runtime without runtime changes. **Connect with
GitHub** uses a publisher-owned GitHub App; connections can instead paste a
personal access token, as the [account setup guide](../connectors/github/SETUP.md)
describes.

Create the app under **Settings → Developer settings → GitHub Apps → New GitHub
App**, preferably owned by Houston's organization:

1. Enter Houston's **GitHub App name**, **Homepage URL** and logo. Under
   **Identifying and authorizing users**, add the publication's redirect URI,
   `<Houston public URL>/oauth/connectors/<hub-publication-id>/callback`, as the
   **Callback URL**. Keep **Expire user authorization tokens** checked: the method
   requires a refresh token. Leave **Request user authorization (OAuth) during
   installation** and **Enable Device Flow** unchecked.
2. Under **Webhook**, clear **Active**; Houston does not receive GitHub events.
3. Set **Repository permissions**: Actions, Administration, Commit statuses,
   Contents, Issues, Pull requests and Workflows to **Read and write**; Checks and
   Metadata to **Read-only**. Set **Organization permissions → Members** to
   **Read-only**, and **Account permissions**: Email addresses **Read-only** and
   Gists **Read and write**.
4. Under **Where can this GitHub App be installed?**, choose **Any account**, then
   **Create GitHub App**.
5. Select **Generate a new client secret**, and enter the **Client ID** and client
   secret in the publication's publisher settings. The app's public page,
   `https://github.com/apps/<slug>`, is where users install it; SETUP sends them
   there through the authorization screen.

User tokens are limited to the intersection of the app's permissions, the user's
own access and the repositories where the app is installed, so users install the app
on their accounts and organizations after authorizing it; SETUP links to the
installation settings. GitHub App permissions are fixed per app, so read-only
connections hold upstream tokens that could write: Houston enforces read-only with
GET-only proxy routes and read-only exports. Requests with user tokens count against
each user's hourly limit (5,000 requests, or 15,000 when an Enterprise Cloud
organization owns the app). Sign-in uses
PKCE and `Accept: application/json` for token replies, which otherwise arrive
form-encoded. Access tokens last 8 hours and refresh tokens about 6 months, rotating
on every refresh. GitHub Apps support only the `offline_access` scope, and the token reply's
`scope` is empty: requesting it would fail Houston's granted-scope check, so the
method requests none and relies on the app's expiring tokens.

The connector covers 145 REST operations, checked on
2026-10-16 against GitHub's [REST OpenAPI
description](https://github.com/github/rest-api-description) 1.1.4 at commit
`798498bd`: users, organizations, teams and app installations; repositories,
forks, contents, archives, branches, commits, comparisons, statuses and checks;
Git refs, trees, blobs and commits; issues, comments, timelines, labels, assignees,
reactions, sub-issues and milestones; pull requests, files, merges, reviews, review
comments and reviewers; releases and assets; Actions workflows, runs, jobs, logs and
artifacts; search; gists; and notifications. Lua pins `X-GitHub-Api-Version:
2026-03-10`, which has no scheduled sunset; GitHub supports a version for at least
24 months after its successor ships.
Notifications are exported only for personal access tokens: GitHub accepts only
classic tokens there, so GitHub App sign-ins omit them and fine-grained tokens get
GitHub's error.

Omitted on purpose: repository deletion, transfer and settings changes, which can
change visibility or archive a repository; GraphQL, whose mutations reach everything
the token allows, including these omissions and sponsorship payments; Actions secrets and
variables; webhooks; deploy keys; collaborator, team, organization and branch
protection or ruleset administration; security alerts, whose secret-scanning
responses contain plaintext secrets; Codespaces, Copilot and packages; GitHub App,
installation token and credential revocation endpoints; and check run writes,
which require installation tokens. Not yet covered: issue and repository events,
commit and gist comments, other reactions, stars and subscriptions, deployments and
environments, Pages, and issue dependencies and sub-issue writes. Release asset
uploads wait for a runtime change: GitHub requires `Content-Length`, which Houston
does not yet send for streamed file bodies.

Credentials go only to the listed routes on `api.github.com`; writes require
read-write access. Branch, ref, path, tag, tree, compare and label values travel as single encoded path segments
through opaque-parameter rules, which GitHub accepts and which keep them from
reaching sub-resources. A credential-free GET rule serves signed download
redirects: `codeload.github.com` for archives, release asset storage on
`githubusercontent.com` hosts, and Actions logs and artifacts on
`*.actions.githubusercontent.com` and `*.blob.core.windows.net`. GitHub's
[meta API](https://api.github.com/meta) lists 140 `productionresultssa<N>` storage
accounts that change over time, so the rule uses the Azure wildcard; Lua follows
only `Location` headers from GitHub on those exact host patterns. The connector sends no
method-override headers and callers cannot add request headers. Responses drop the query from `download_url` and remove `temp_clone_token`, which
for private repositories carry tokens usable outside Houston.

This is a new registration with no existing connections. Fixtures cover both
methods and access levels, routes, opaque encoding, bodies, downloads through
redirects and error mapping; GitHub App sign-in, token refresh, paging and
a disposable write remain to verify live, as does the SETUP install route. Encoded
`%2F` branch, ref, path and compare values were checked with unauthenticated
requests on public repositories.

GitHub's icon is the official Invertocat (`GitHub_Invertocat_Black.svg`) from the
[brand kit](https://brand.github.com/GitHub_Logos.zip) linked from
[github.com/logos](https://github.com/logos), retrieved 2026-10-16, unchanged.
GitHub permits it to show that a project integrates with GitHub. GitHub® and the
Invertocat logo are trademarks of GitHub, Inc.
