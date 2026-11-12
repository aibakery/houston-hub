# Umami API coverage

Reference: [Umami 3.4.1 OpenAPI](https://github.com/umami-software/docs/blob/1460232d912a8f83402a7e2920b6e139963ec8f7/openapi.json), reviewed 2026-11-12.

Authentication uses a configured API key (or an existing self-hosted bearer token). Login and two-factor login verification establish that credential outside caller scripts; their credentials are never accepted as operation arguments. All other documented routes are mapped below. Cloud omits `/users/*` and `/me/password`, which its gateway disallows. Provider roles, enabled features, database engine and subscription still apply.

| Method | API path | Function / handling | Access area |
| --- | --- | --- | --- |
| POST | `/api/2fa/disable` | `disableTwoFactor` | account |
| POST | `/api/2fa/setup/cancel` | `cancelTwoFactorSetup` | account |
| POST | `/api/2fa/setup/confirm` | `confirmTwoFactorSetup` | account |
| POST | `/api/2fa/setup/initiate` | `initiateTwoFactorSetup` | account |
| GET | `/api/2fa/status` | `getTwoFactorStatus` | account |
| POST | `/api/2fa/verify` | Connection authentication | account |
| POST | `/api/admin/2fa/global` | `postAdmin2faGlobal` | administration |
| GET | `/api/admin/teams` | `getAdminTeams` | administration |
| POST | `/api/admin/teams/{teamId}/2fa` | `postAdminTeamsTeamId2fa` | administration |
| GET | `/api/admin/users` | `getAdminUsers` | administration |
| DELETE | `/api/admin/users/{userId}/2fa` | `deleteAdminUsersUserId2fa` | administration |
| GET | `/api/admin/users/{userId}/2fa` | `getAdminUsersUserId2fa` | administration |
| POST | `/api/admin/users/{userId}/2fa` | `postAdminUsersUserId2fa` | administration |
| GET | `/api/admin/websites` | `getAdminWebsites` | administration |
| POST | `/api/auth/login` | Connection authentication | account |
| POST | `/api/auth/logout` | `logout` | account |
| POST | `/api/auth/sso` | `sso` | account |
| GET | `/api/auth/subscription` | `getSubscription` | account |
| POST | `/api/auth/verify` | `verify` | account |
| POST | `/api/batch` | `batch` | collection |
| GET | `/api/boards` | `getBoards` | boards |
| POST | `/api/boards` | `createBoard` | boards |
| DELETE | `/api/boards/{boardId}` | `deleteBoard` | boards |
| GET | `/api/boards/{boardId}` | `getBoard` | boards |
| POST | `/api/boards/{boardId}` | `updateBoard` | boards |
| POST | `/api/boards/{boardId}/clone` | `cloneBoard` | boards |
| GET | `/api/boards/{boardId}/shares` | `getBoardShares` | boards |
| POST | `/api/boards/{boardId}/shares` | `createBoardShare` | boards |
| GET | `/api/dashboard` | `getDashboard` | boards |
| POST | `/api/dashboard` | `postDashboard` | boards |
| GET | `/api/heartbeat` | `getHeartbeat` | system |
| GET | `/api/links` | `getLinks` | links |
| POST | `/api/links` | `createLink` | links |
| GET | `/api/links/charts` | `getLinksCharts` | links |
| DELETE | `/api/links/{linkId}` | `deleteLink` | links |
| GET | `/api/links/{linkId}` | `getLink` | links |
| POST | `/api/links/{linkId}` | `updateLink` | links |
| GET | `/api/links/{linkId}/shares` | `getLinkShares` | links |
| POST | `/api/links/{linkId}/shares` | `createLinkShare` | links |
| GET | `/api/me` | `getMe` | account |
| GET | `/api/me/api-keys` | `getMyApiKeys` | account |
| POST | `/api/me/api-keys` | `createMyApiKey` | account |
| DELETE | `/api/me/api-keys/{keyId}` | `deleteMyApiKey` | account |
| POST | `/api/me/password` | `updateMyPassword` | account |
| GET | `/api/me/teams` | `getMyTeams` | account |
| GET | `/api/me/websites` | `getMyWebsites` | account |
| GET | `/api/pixels` | `getPixels` | pixels |
| POST | `/api/pixels` | `createPixel` | pixels |
| GET | `/api/pixels/charts` | `getPixelsCharts` | pixels |
| DELETE | `/api/pixels/{pixelId}` | `deletePixel` | pixels |
| GET | `/api/pixels/{pixelId}` | `getPixel` | pixels |
| POST | `/api/pixels/{pixelId}` | `updatePixel` | pixels |
| GET | `/api/pixels/{pixelId}/shares` | `getPixelShares` | pixels |
| POST | `/api/pixels/{pixelId}/shares` | `createPixelShare` | pixels |
| GET | `/api/realtime/{websiteId}` | `getRealtime` | analytics |
| POST | `/api/record` | `record` | collection |
| GET | `/api/scripts/telemetry` | `getScriptsTelemetry` | system |
| POST | `/api/send` | `send` | collection |
| POST | `/api/share` | `createShare` | shares |
| DELETE | `/api/share/id/{shareId}` | `deleteShare` | shares |
| GET | `/api/share/id/{shareId}` | `getShare` | shares |
| POST | `/api/share/id/{shareId}` | `updateShare` | shares |
| GET | `/api/share/{slug}` | `getShareBySlug` | shares |
| GET | `/api/teams` | `getTeams` | teams |
| POST | `/api/teams` | `createTeam` | teams |
| POST | `/api/teams/join` | `joinTeam` | teams |
| DELETE | `/api/teams/{teamId}` | `deleteTeam` | teams |
| GET | `/api/teams/{teamId}` | `getTeam` | teams |
| POST | `/api/teams/{teamId}` | `updateTeam` | teams |
| GET | `/api/teams/{teamId}/boards` | `getTeamBoards` | teams |
| GET | `/api/teams/{teamId}/links` | `getTeamLinks` | teams |
| GET | `/api/teams/{teamId}/pixels` | `getTeamPixels` | teams |
| GET | `/api/teams/{teamId}/users` | `getTeamUsers` | teams |
| POST | `/api/teams/{teamId}/users` | `createTeamUser` | teams |
| DELETE | `/api/teams/{teamId}/users/{userId}` | `deleteTeamUser` | teams |
| GET | `/api/teams/{teamId}/users/{userId}` | `getTeamUser` | teams |
| POST | `/api/teams/{teamId}/users/{userId}` | `updateTeamUser` | teams |
| GET | `/api/teams/{teamId}/websites` | `getTeamWebsites` | teams |
| POST | `/api/users` | `createUser` | administration |
| DELETE | `/api/users/{userId}` | `deleteUser` | administration |
| GET | `/api/users/{userId}` | `getUser` | administration |
| POST | `/api/users/{userId}` | `updateUser` | administration |
| GET | `/api/users/{userId}/teams` | `getUserTeams` | administration |
| GET | `/api/users/{userId}/websites` | `getUserWebsites` | administration |
| GET | `/api/websites` | `listWebsites` | websites |
| POST | `/api/websites` | `createWebsite` | websites |
| GET | `/api/websites/charts` | `getWebsitesCharts` | websites |
| DELETE | `/api/websites/{websiteId}` | `deleteWebsite` | websites |
| GET | `/api/websites/{websiteId}` | `getWebsite` | websites |
| POST | `/api/websites/{websiteId}` | `updateWebsite` | websites |
| GET | `/api/websites/{websiteId}/active` | `getWebsiteActive` | analytics |
| GET | `/api/websites/{websiteId}/annotations` | `getWebsiteAnnotations` | reports |
| POST | `/api/websites/{websiteId}/annotations` | `createWebsiteAnnotation` | reports |
| DELETE | `/api/websites/{websiteId}/annotations/{annotationId}` | `deleteWebsiteAnnotation` | reports |
| GET | `/api/websites/{websiteId}/annotations/{annotationId}` | `getWebsiteAnnotation` | reports |
| POST | `/api/websites/{websiteId}/annotations/{annotationId}` | `updateWebsiteAnnotation` | reports |
| GET | `/api/websites/{websiteId}/attribution` | `getWebsiteAttribution` | analytics |
| GET | `/api/websites/{websiteId}/breakdown` | `getWebsiteBreakdown` | analytics |
| GET | `/api/websites/{websiteId}/daterange` | `getWebsiteDateRange` | analytics |
| GET | `/api/websites/{websiteId}/errors` | `getWebsiteErrors` | errors |
| GET | `/api/websites/{websiteId}/errors/stats` | `getWebsiteErrorStats` | errors |
| GET | `/api/websites/{websiteId}/errors/values` | `getWebsiteErrorValues` | errors |
| GET | `/api/websites/{websiteId}/errors/{issueId}` | `getWebsiteErrorIssue` | errors |
| PATCH | `/api/websites/{websiteId}/errors/{issueId}` | `updateWebsiteErrorIssue` | errors |
| GET | `/api/websites/{websiteId}/errors/{issueId}/events` | `getWebsiteErrorEvents` | errors |
| GET | `/api/websites/{websiteId}/errors/{issueId}/events/{eventId}` | `getWebsiteErrorEvent` | errors |
| GET | `/api/websites/{websiteId}/errors/{issueId}/values` | `getWebsiteErrorIssueValues` | errors |
| GET | `/api/websites/{websiteId}/event-data` | `getEventData` | analytics |
| GET | `/api/websites/{websiteId}/event-data-pivot` | `getEventDataPivot` | analytics |
| GET | `/api/websites/{websiteId}/event-data-pivot/array-series` | `getEventDataArraySeries` | analytics |
| GET | `/api/websites/{websiteId}/event-data-pivot/date-series` | `getEventDataDateSeries` | analytics |
| GET | `/api/websites/{websiteId}/event-data-pivot/numeric-series` | `getEventDataNumericSeries` | analytics |
| GET | `/api/websites/{websiteId}/event-data-pivot/numeric-stats` | `getEventDataNumericStats` | analytics |
| GET | `/api/websites/{websiteId}/event-data-pivot/property-series` | `getEventDataPropertySeries` | analytics |
| GET | `/api/websites/{websiteId}/event-data/events` | `getEventDataEvents` | analytics |
| GET | `/api/websites/{websiteId}/event-data/fields` | `getEventDataFields` | analytics |
| GET | `/api/websites/{websiteId}/event-data/properties` | `getEventDataProperties` | analytics |
| GET | `/api/websites/{websiteId}/event-data/stats` | `getEventDataStats` | analytics |
| GET | `/api/websites/{websiteId}/event-data/values` | `getEventDataValues` | analytics |
| GET | `/api/websites/{websiteId}/event-data/{eventId}` | `getEventDataById` | analytics |
| GET | `/api/websites/{websiteId}/events` | `getWebsiteEvents` | analytics |
| GET | `/api/websites/{websiteId}/events/series` | `getWebsiteEventSeries` | analytics |
| GET | `/api/websites/{websiteId}/events/stats` | `getWebsiteEventStats` | analytics |
| GET | `/api/websites/{websiteId}/export` | `exportWebsite` | analytics |
| GET | `/api/websites/{websiteId}/funnels` | `getWebsiteFunnels` | reports |
| POST | `/api/websites/{websiteId}/funnels` | `createWebsiteFunnel` | reports |
| GET | `/api/websites/{websiteId}/funnels/stats` | `getWebsiteFunnelStats` | reports |
| DELETE | `/api/websites/{websiteId}/funnels/{funnelId}` | `deleteWebsiteFunnel` | reports |
| GET | `/api/websites/{websiteId}/funnels/{funnelId}` | `getWebsiteFunnel` | reports |
| POST | `/api/websites/{websiteId}/funnels/{funnelId}` | `updateWebsiteFunnel` | reports |
| GET | `/api/websites/{websiteId}/funnels/{funnelId}/stats` | `getWebsiteSavedFunnelStats` | reports |
| GET | `/api/websites/{websiteId}/goals` | `getWebsiteGoals` | reports |
| POST | `/api/websites/{websiteId}/goals` | `createWebsiteGoal` | reports |
| GET | `/api/websites/{websiteId}/goals/stats` | `getWebsiteGoalStats` | reports |
| DELETE | `/api/websites/{websiteId}/goals/{goalId}` | `deleteWebsiteGoal` | reports |
| GET | `/api/websites/{websiteId}/goals/{goalId}` | `getWebsiteGoal` | reports |
| POST | `/api/websites/{websiteId}/goals/{goalId}` | `updateWebsiteGoal` | reports |
| GET | `/api/websites/{websiteId}/goals/{goalId}/stats` | `getWebsiteSavedGoalStats` | reports |
| GET | `/api/websites/{websiteId}/heatmaps` | `getWebsiteHeatmaps` | analytics |
| GET | `/api/websites/{websiteId}/journeys` | `getWebsiteJourneys` | analytics |
| GET | `/api/websites/{websiteId}/metrics` | `getWebsiteMetrics` | analytics |
| GET | `/api/websites/{websiteId}/metrics/expanded` | `getWebsiteExpandedMetrics` | analytics |
| GET | `/api/websites/{websiteId}/pageviews` | `getWebsitePageviews` | analytics |
| GET | `/api/websites/{websiteId}/performance/chart` | `getWebsitePerformanceChart` | analytics |
| GET | `/api/websites/{websiteId}/performance/metrics` | `getWebsitePerformanceMetrics` | analytics |
| GET | `/api/websites/{websiteId}/performance/stats` | `getWebsitePerformanceStats` | analytics |
| GET | `/api/websites/{websiteId}/recorder` | `getWebsiteRecorderConfig` | replays |
| GET | `/api/websites/{websiteId}/replays` | `getWebsiteReplays` | replays |
| GET | `/api/websites/{websiteId}/replays/saved` | `getWebsiteSavedReplays` | replays |
| GET | `/api/websites/{websiteId}/replays/saved/{replayId}` | `getWebsiteReplaySaved` | replays |
| POST | `/api/websites/{websiteId}/replays/saved/{replayId}` | `saveWebsiteReplay` | replays |
| GET | `/api/websites/{websiteId}/replays/{replayId}` | `getWebsiteReplay` | replays |
| POST | `/api/websites/{websiteId}/reset` | `resetWebsite` | websites |
| GET | `/api/websites/{websiteId}/retention` | `getWebsiteRetention` | analytics |
| GET | `/api/websites/{websiteId}/revenue/chart` | `getWebsiteRevenueChart` | analytics |
| GET | `/api/websites/{websiteId}/revenue/metrics` | `getWebsiteRevenueMetrics` | analytics |
| GET | `/api/websites/{websiteId}/revenue/sessions` | `getWebsiteRevenueSessions` | analytics |
| GET | `/api/websites/{websiteId}/revenue/stats` | `getWebsiteRevenueStats` | analytics |
| GET | `/api/websites/{websiteId}/segments` | `getWebsiteSegments` | reports |
| POST | `/api/websites/{websiteId}/segments` | `createWebsiteSegment` | reports |
| DELETE | `/api/websites/{websiteId}/segments/{segmentId}` | `deleteWebsiteSegment` | reports |
| GET | `/api/websites/{websiteId}/segments/{segmentId}` | `getWebsiteSegment` | reports |
| POST | `/api/websites/{websiteId}/segments/{segmentId}` | `updateWebsiteSegment` | reports |
| GET | `/api/websites/{websiteId}/session-data-pivot` | `getSessionDataPivot` | analytics |
| GET | `/api/websites/{websiteId}/session-data/array-series` | `getSessionDataArraySeries` | analytics |
| GET | `/api/websites/{websiteId}/session-data/date-series` | `getSessionDataDateSeries` | analytics |
| GET | `/api/websites/{websiteId}/session-data/numeric-series` | `getSessionDataNumericSeries` | analytics |
| GET | `/api/websites/{websiteId}/session-data/numeric-stats` | `getSessionDataNumericStats` | analytics |
| GET | `/api/websites/{websiteId}/session-data/properties` | `getSessionDataProperties` | analytics |
| GET | `/api/websites/{websiteId}/session-data/property-series` | `getSessionDataPropertySeries` | analytics |
| GET | `/api/websites/{websiteId}/session-data/stats` | `getSessionDataStats` | analytics |
| GET | `/api/websites/{websiteId}/session-data/values` | `getSessionDataValues` | analytics |
| GET | `/api/websites/{websiteId}/sessions` | `getWebsiteSessions` | analytics |
| GET | `/api/websites/{websiteId}/sessions/stats` | `getWebsiteSessionStats` | analytics |
| GET | `/api/websites/{websiteId}/sessions/weekly` | `getWebsiteSessionsWeekly` | analytics |
| DELETE | `/api/websites/{websiteId}/sessions/{sessionId}` | `deleteWebsiteSession` | analytics |
| GET | `/api/websites/{websiteId}/sessions/{sessionId}` | `getWebsiteSession` | analytics |
| GET | `/api/websites/{websiteId}/sessions/{sessionId}/activity` | `getWebsiteSessionActivity` | analytics |
| GET | `/api/websites/{websiteId}/sessions/{sessionId}/properties` | `getWebsiteSessionProperties` | analytics |
| GET | `/api/websites/{websiteId}/sessions/{sessionId}/replays` | `getWebsiteSessionReplays` | replays |
| GET | `/api/websites/{websiteId}/shares` | `getWebsiteShares` | shares |
| POST | `/api/websites/{websiteId}/shares` | `createWebsiteShare` | shares |
| GET | `/api/websites/{websiteId}/stats` | `getWebsiteStats` | analytics |
| POST | `/api/websites/{websiteId}/transfer` | `transferWebsite` | websites |
| GET | `/api/websites/{websiteId}/utm/metrics` | `getWebsiteUtmMetrics` | analytics |
| GET | `/api/websites/{websiteId}/values` | `getWebsiteValues` | analytics |

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
