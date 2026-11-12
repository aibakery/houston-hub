# Umami API coverage

Reference: [Umami 3.4.1 OpenAPI](https://github.com/umami-software/docs/blob/1460232d912a8f83402a7e2920b6e139963ec8f7/openapi.json), reviewed 2026-11-12.

Authentication uses a configured API key (or an existing self-hosted bearer token). Login and two-factor login verification establish that credential outside caller scripts; their credentials are never accepted as operation arguments. All other documented routes are mapped below. Cloud omits `/users/*` and `/me/password`, which its gateway disallows. Provider roles, enabled features, database engine and subscription still apply.

## Namespace discovery

Operations are grouped in ordinary resource tables. Start with `help()` to see
up to ten root namespaces, then explore the resource you need. Website analytics,
events, sessions, reports and recordings have their own child namespaces. Each
namespace lists only its immediate functions and children; detailed schemas and
examples appear when you ask for a function.

```lua
umami.help()                         -- Root resource summaries
umami.websites.help()                -- Website operations and child namespaces
umami.websites.analytics.help()      -- Traffic and visitor operations
umami.websites.analytics.help("metrics") -- Parameters, results and examples

local sites = umami.websites.list({page = 1, pageSize = 20})
local pages = umami.websites.analytics.metrics({
    websiteId = sites.data[1].id,
    period = "7d",
    type = "path",
    filter = {country = "US", browser = "Chrome"},
})
```

The root resources are `websites`, `boards`, `links`, `pixels`, `shares`, `teams`,
`profile`, `administration`, `collection` and `system`. `profile` contains current
user and credential operations. Namespace organization is independent of access
areas: for example, website analytics and website settings retain their separate
permissions. Only enabled branches appear. All 184 operations remain available
with full access on a supported self-hosted installation; Cloud excludes its
unsupported routes.

## Endpoint inventory

| Method | API path | Function / handling | Access area |
| --- | --- | --- | --- |
| POST | `/api/2fa/disable` | `profile.twoFactor.disable` | account |
| POST | `/api/2fa/setup/cancel` | `profile.twoFactor.cancelSetup` | account |
| POST | `/api/2fa/setup/confirm` | `profile.twoFactor.confirmSetup` | account |
| POST | `/api/2fa/setup/initiate` | `profile.twoFactor.initiateSetup` | account |
| GET | `/api/2fa/status` | `profile.twoFactor.status` | account |
| POST | `/api/2fa/verify` | Connection authentication | account |
| POST | `/api/admin/2fa/global` | `administration.setTwoFactorPolicy` | administration |
| GET | `/api/admin/teams` | `administration.teams` | administration |
| POST | `/api/admin/teams/{teamId}/2fa` | `administration.setTeamTwoFactorPolicy` | administration |
| GET | `/api/admin/users` | `administration.users.list` | administration |
| DELETE | `/api/admin/users/{userId}/2fa` | `administration.users.twoFactor.disable` | administration |
| GET | `/api/admin/users/{userId}/2fa` | `administration.users.twoFactor.status` | administration |
| POST | `/api/admin/users/{userId}/2fa` | `administration.users.twoFactor.setPolicy` | administration |
| GET | `/api/admin/websites` | `administration.websites` | administration |
| POST | `/api/auth/login` | Connection authentication | account |
| POST | `/api/auth/logout` | `profile.logout` | account |
| POST | `/api/auth/sso` | `profile.sso` | account |
| GET | `/api/auth/subscription` | `profile.subscription` | account |
| POST | `/api/auth/verify` | `profile.verify` | account |
| POST | `/api/batch` | `collection.batch` | collection |
| GET | `/api/boards` | `boards.list` | boards |
| POST | `/api/boards` | `boards.create` | boards |
| DELETE | `/api/boards/{boardId}` | `boards.delete` | boards |
| GET | `/api/boards/{boardId}` | `boards.get` | boards |
| POST | `/api/boards/{boardId}` | `boards.update` | boards |
| POST | `/api/boards/{boardId}/clone` | `boards.clone` | boards |
| GET | `/api/boards/{boardId}/shares` | `boards.shares.list` | boards |
| POST | `/api/boards/{boardId}/shares` | `boards.shares.create` | boards |
| GET | `/api/dashboard` | `boards.dashboard.get` | boards |
| POST | `/api/dashboard` | `boards.dashboard.update` | boards |
| GET | `/api/heartbeat` | `system.heartbeat` | system |
| GET | `/api/links` | `links.list` | links |
| POST | `/api/links` | `links.create` | links |
| GET | `/api/links/charts` | `links.charts` | links |
| DELETE | `/api/links/{linkId}` | `links.delete` | links |
| GET | `/api/links/{linkId}` | `links.get` | links |
| POST | `/api/links/{linkId}` | `links.update` | links |
| GET | `/api/links/{linkId}/shares` | `links.shares.list` | links |
| POST | `/api/links/{linkId}/shares` | `links.shares.create` | links |
| GET | `/api/me` | `profile.get` | account |
| GET | `/api/me/api-keys` | `profile.apiKeys.list` | account |
| POST | `/api/me/api-keys` | `profile.apiKeys.create` | account |
| DELETE | `/api/me/api-keys/{keyId}` | `profile.apiKeys.delete` | account |
| POST | `/api/me/password` | `profile.updatePassword` | account |
| GET | `/api/me/teams` | `profile.teams` | account |
| GET | `/api/me/websites` | `profile.websites` | account |
| GET | `/api/pixels` | `pixels.list` | pixels |
| POST | `/api/pixels` | `pixels.create` | pixels |
| GET | `/api/pixels/charts` | `pixels.charts` | pixels |
| DELETE | `/api/pixels/{pixelId}` | `pixels.delete` | pixels |
| GET | `/api/pixels/{pixelId}` | `pixels.get` | pixels |
| POST | `/api/pixels/{pixelId}` | `pixels.update` | pixels |
| GET | `/api/pixels/{pixelId}/shares` | `pixels.shares.list` | pixels |
| POST | `/api/pixels/{pixelId}/shares` | `pixels.shares.create` | pixels |
| GET | `/api/realtime/{websiteId}` | `websites.analytics.realtime` | analytics |
| POST | `/api/record` | `collection.record` | collection |
| GET | `/api/scripts/telemetry` | `system.telemetryScript` | system |
| POST | `/api/send` | `collection.send` | collection |
| POST | `/api/share` | `shares.create` | shares |
| DELETE | `/api/share/id/{shareId}` | `shares.delete` | shares |
| GET | `/api/share/id/{shareId}` | `shares.get` | shares |
| POST | `/api/share/id/{shareId}` | `shares.update` | shares |
| GET | `/api/share/{slug}` | `shares.bySlug` | shares |
| GET | `/api/teams` | `teams.list` | teams |
| POST | `/api/teams` | `teams.create` | teams |
| POST | `/api/teams/join` | `teams.join` | teams |
| DELETE | `/api/teams/{teamId}` | `teams.delete` | teams |
| GET | `/api/teams/{teamId}` | `teams.get` | teams |
| POST | `/api/teams/{teamId}` | `teams.update` | teams |
| GET | `/api/teams/{teamId}/boards` | `teams.boards` | teams |
| GET | `/api/teams/{teamId}/links` | `teams.links` | teams |
| GET | `/api/teams/{teamId}/pixels` | `teams.pixels` | teams |
| GET | `/api/teams/{teamId}/users` | `teams.members.list` | teams |
| POST | `/api/teams/{teamId}/users` | `teams.members.create` | teams |
| DELETE | `/api/teams/{teamId}/users/{userId}` | `teams.members.delete` | teams |
| GET | `/api/teams/{teamId}/users/{userId}` | `teams.members.get` | teams |
| POST | `/api/teams/{teamId}/users/{userId}` | `teams.members.update` | teams |
| GET | `/api/teams/{teamId}/websites` | `teams.websites` | teams |
| POST | `/api/users` | `administration.users.create` | administration |
| DELETE | `/api/users/{userId}` | `administration.users.delete` | administration |
| GET | `/api/users/{userId}` | `administration.users.get` | administration |
| POST | `/api/users/{userId}` | `administration.users.update` | administration |
| GET | `/api/users/{userId}/teams` | `administration.users.teams` | administration |
| GET | `/api/users/{userId}/websites` | `administration.users.websites` | administration |
| GET | `/api/websites` | `websites.list` | websites |
| POST | `/api/websites` | `websites.create` | websites |
| GET | `/api/websites/charts` | `websites.charts` | websites |
| DELETE | `/api/websites/{websiteId}` | `websites.delete` | websites |
| GET | `/api/websites/{websiteId}` | `websites.get` | websites |
| POST | `/api/websites/{websiteId}` | `websites.update` | websites |
| GET | `/api/websites/{websiteId}/active` | `websites.analytics.active` | analytics |
| GET | `/api/websites/{websiteId}/annotations` | `websites.annotations.list` | reports |
| POST | `/api/websites/{websiteId}/annotations` | `websites.annotations.create` | reports |
| DELETE | `/api/websites/{websiteId}/annotations/{annotationId}` | `websites.annotations.delete` | reports |
| GET | `/api/websites/{websiteId}/annotations/{annotationId}` | `websites.annotations.get` | reports |
| POST | `/api/websites/{websiteId}/annotations/{annotationId}` | `websites.annotations.update` | reports |
| GET | `/api/websites/{websiteId}/attribution` | `websites.analytics.attribution` | analytics |
| GET | `/api/websites/{websiteId}/breakdown` | `websites.analytics.breakdown` | analytics |
| GET | `/api/websites/{websiteId}/daterange` | `websites.analytics.dateRange` | analytics |
| GET | `/api/websites/{websiteId}/errors` | `websites.errors.list` | errors |
| GET | `/api/websites/{websiteId}/errors/stats` | `websites.errors.stats` | errors |
| GET | `/api/websites/{websiteId}/errors/values` | `websites.errors.values` | errors |
| GET | `/api/websites/{websiteId}/errors/{issueId}` | `websites.errors.issue` | errors |
| PATCH | `/api/websites/{websiteId}/errors/{issueId}` | `websites.errors.updateIssue` | errors |
| GET | `/api/websites/{websiteId}/errors/{issueId}/events` | `websites.errors.events` | errors |
| GET | `/api/websites/{websiteId}/errors/{issueId}/events/{eventId}` | `websites.errors.event` | errors |
| GET | `/api/websites/{websiteId}/errors/{issueId}/values` | `websites.errors.issueValues` | errors |
| GET | `/api/websites/{websiteId}/event-data` | `websites.eventData.list` | analytics |
| GET | `/api/websites/{websiteId}/event-data-pivot` | `websites.eventData.pivot` | analytics |
| GET | `/api/websites/{websiteId}/event-data-pivot/array-series` | `websites.eventData.arraySeries` | analytics |
| GET | `/api/websites/{websiteId}/event-data-pivot/date-series` | `websites.eventData.dateSeries` | analytics |
| GET | `/api/websites/{websiteId}/event-data-pivot/numeric-series` | `websites.eventData.numericSeries` | analytics |
| GET | `/api/websites/{websiteId}/event-data-pivot/numeric-stats` | `websites.eventData.numericStats` | analytics |
| GET | `/api/websites/{websiteId}/event-data-pivot/property-series` | `websites.eventData.propertySeries` | analytics |
| GET | `/api/websites/{websiteId}/event-data/events` | `websites.eventData.events` | analytics |
| GET | `/api/websites/{websiteId}/event-data/fields` | `websites.eventData.fields` | analytics |
| GET | `/api/websites/{websiteId}/event-data/properties` | `websites.eventData.properties` | analytics |
| GET | `/api/websites/{websiteId}/event-data/stats` | `websites.eventData.stats` | analytics |
| GET | `/api/websites/{websiteId}/event-data/values` | `websites.eventData.values` | analytics |
| GET | `/api/websites/{websiteId}/event-data/{eventId}` | `websites.eventData.get` | analytics |
| GET | `/api/websites/{websiteId}/events` | `websites.events.list` | analytics |
| GET | `/api/websites/{websiteId}/events/series` | `websites.events.series` | analytics |
| GET | `/api/websites/{websiteId}/events/stats` | `websites.events.stats` | analytics |
| GET | `/api/websites/{websiteId}/export` | `websites.export` | analytics |
| GET | `/api/websites/{websiteId}/funnels` | `websites.funnels.list` | reports |
| POST | `/api/websites/{websiteId}/funnels` | `websites.funnels.create` | reports |
| GET | `/api/websites/{websiteId}/funnels/stats` | `websites.funnels.stats` | reports |
| DELETE | `/api/websites/{websiteId}/funnels/{funnelId}` | `websites.funnels.delete` | reports |
| GET | `/api/websites/{websiteId}/funnels/{funnelId}` | `websites.funnels.get` | reports |
| POST | `/api/websites/{websiteId}/funnels/{funnelId}` | `websites.funnels.update` | reports |
| GET | `/api/websites/{websiteId}/funnels/{funnelId}/stats` | `websites.funnels.savedStats` | reports |
| GET | `/api/websites/{websiteId}/goals` | `websites.goals.list` | reports |
| POST | `/api/websites/{websiteId}/goals` | `websites.goals.create` | reports |
| GET | `/api/websites/{websiteId}/goals/stats` | `websites.goals.stats` | reports |
| DELETE | `/api/websites/{websiteId}/goals/{goalId}` | `websites.goals.delete` | reports |
| GET | `/api/websites/{websiteId}/goals/{goalId}` | `websites.goals.get` | reports |
| POST | `/api/websites/{websiteId}/goals/{goalId}` | `websites.goals.update` | reports |
| GET | `/api/websites/{websiteId}/goals/{goalId}/stats` | `websites.goals.savedStats` | reports |
| GET | `/api/websites/{websiteId}/heatmaps` | `websites.replays.heatmaps` | analytics |
| GET | `/api/websites/{websiteId}/journeys` | `websites.analytics.journeys` | analytics |
| GET | `/api/websites/{websiteId}/metrics` | `websites.analytics.metrics` | analytics |
| GET | `/api/websites/{websiteId}/metrics/expanded` | `websites.analytics.expandedMetrics` | analytics |
| GET | `/api/websites/{websiteId}/pageviews` | `websites.analytics.pageviews` | analytics |
| GET | `/api/websites/{websiteId}/performance/chart` | `websites.performance.chart` | analytics |
| GET | `/api/websites/{websiteId}/performance/metrics` | `websites.performance.metrics` | analytics |
| GET | `/api/websites/{websiteId}/performance/stats` | `websites.performance.stats` | analytics |
| GET | `/api/websites/{websiteId}/recorder` | `websites.replays.recorderConfig` | replays |
| GET | `/api/websites/{websiteId}/replays` | `websites.replays.list` | replays |
| GET | `/api/websites/{websiteId}/replays/saved` | `websites.replays.saved` | replays |
| GET | `/api/websites/{websiteId}/replays/saved/{replayId}` | `websites.replays.isSaved` | replays |
| POST | `/api/websites/{websiteId}/replays/saved/{replayId}` | `websites.replays.save` | replays |
| GET | `/api/websites/{websiteId}/replays/{replayId}` | `websites.replays.get` | replays |
| POST | `/api/websites/{websiteId}/reset` | `websites.reset` | websites |
| GET | `/api/websites/{websiteId}/retention` | `websites.analytics.retention` | analytics |
| GET | `/api/websites/{websiteId}/revenue/chart` | `websites.revenue.chart` | analytics |
| GET | `/api/websites/{websiteId}/revenue/metrics` | `websites.revenue.metrics` | analytics |
| GET | `/api/websites/{websiteId}/revenue/sessions` | `websites.revenue.sessions` | analytics |
| GET | `/api/websites/{websiteId}/revenue/stats` | `websites.revenue.stats` | analytics |
| GET | `/api/websites/{websiteId}/segments` | `websites.segments.list` | reports |
| POST | `/api/websites/{websiteId}/segments` | `websites.segments.create` | reports |
| DELETE | `/api/websites/{websiteId}/segments/{segmentId}` | `websites.segments.delete` | reports |
| GET | `/api/websites/{websiteId}/segments/{segmentId}` | `websites.segments.get` | reports |
| POST | `/api/websites/{websiteId}/segments/{segmentId}` | `websites.segments.update` | reports |
| GET | `/api/websites/{websiteId}/session-data-pivot` | `websites.sessionData.pivot` | analytics |
| GET | `/api/websites/{websiteId}/session-data/array-series` | `websites.sessionData.arraySeries` | analytics |
| GET | `/api/websites/{websiteId}/session-data/date-series` | `websites.sessionData.dateSeries` | analytics |
| GET | `/api/websites/{websiteId}/session-data/numeric-series` | `websites.sessionData.numericSeries` | analytics |
| GET | `/api/websites/{websiteId}/session-data/numeric-stats` | `websites.sessionData.numericStats` | analytics |
| GET | `/api/websites/{websiteId}/session-data/properties` | `websites.sessionData.properties` | analytics |
| GET | `/api/websites/{websiteId}/session-data/property-series` | `websites.sessionData.propertySeries` | analytics |
| GET | `/api/websites/{websiteId}/session-data/stats` | `websites.sessionData.stats` | analytics |
| GET | `/api/websites/{websiteId}/session-data/values` | `websites.sessionData.values` | analytics |
| GET | `/api/websites/{websiteId}/sessions` | `websites.sessions.list` | analytics |
| GET | `/api/websites/{websiteId}/sessions/stats` | `websites.sessions.stats` | analytics |
| GET | `/api/websites/{websiteId}/sessions/weekly` | `websites.sessions.weekly` | analytics |
| DELETE | `/api/websites/{websiteId}/sessions/{sessionId}` | `websites.sessions.delete` | analytics |
| GET | `/api/websites/{websiteId}/sessions/{sessionId}` | `websites.sessions.get` | analytics |
| GET | `/api/websites/{websiteId}/sessions/{sessionId}/activity` | `websites.sessions.activity` | analytics |
| GET | `/api/websites/{websiteId}/sessions/{sessionId}/properties` | `websites.sessions.properties` | analytics |
| GET | `/api/websites/{websiteId}/sessions/{sessionId}/replays` | `websites.sessions.replays` | replays |
| GET | `/api/websites/{websiteId}/shares` | `websites.shares.list` | shares |
| POST | `/api/websites/{websiteId}/shares` | `websites.shares.create` | shares |
| GET | `/api/websites/{websiteId}/stats` | `websites.analytics.stats` | analytics |
| POST | `/api/websites/{websiteId}/transfer` | `websites.transfer` | websites |
| GET | `/api/websites/{websiteId}/utm/metrics` | `websites.analytics.utmMetrics` | analytics |
| GET | `/api/websites/{websiteId}/values` | `websites.analytics.values` | analytics |

## Source checks beyond the specification

The [Umami implementation](https://github.com/umami-software/umami/tree/d3c62a805beda8643cb468924dda38617fb4c286/src/app/api)
provides details missing or mis-inferred in the published schema:

- Replay retrieval accepts `until`, `chunkIndex` and `eventIndex`. Empty replays
  return null session/timestamp fields.
- Collection accepts `x-umami-cache`; nonempty recording uploads need it and have
  a 1,000,000-byte request limit. Batch responses preserve per-item errors.
- Date-range helpers accept `period`, including export and chart routes.
- Board types are `mixed`, `website`, `pixel`, `link` and legacy `open`; updates
  also accept `dashboard`. The specification's empty enum is incomplete.
- Creating an API key requires a name string of 1–255 characters.
- Analytics accepts numbered dimension filters and `pf_`, `epfN`, `spfN` property
  filters. Presence flags such as `includeTeams` enable their behavior for any
  nonempty string; the connector omits them when the caller passes boolean false.

The schema data and official icon retain Umami's [MIT notice](lib/LICENSE.md).
