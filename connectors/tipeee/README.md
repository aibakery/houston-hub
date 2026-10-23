---
description: Manage Tipeee creator pages, rewards, news, supporters, reports and messages through its unofficial website API.
---
# Tipeee

Connect a Tipeee creator account with its session access token. Read projects,
rewards, news, comments, campaign supporters, payments, statistics and inbox
messages. Read-write access also manages creator content, sends messages,
requests payouts, uploads media, exports reports and configures streaming widgets.

This connector uses the website's unofficial API v2.0, inspected on 2026-10-23.
The [official general documentation](https://api.tipeee.com/api/doc/default)
covers only a small subset; the [partner documentation](https://api.tipeee.com/api/doc/partner)
is for tipper integrations. Creator management contracts come from the current
[first-party website source](https://en.tipeee.com/_nuxt/20261022134411.30.js).
They can change without notice. No authenticated live requests have been used to
verify this implementation; fixtures exercise the observed request contracts.

Use `help()` for operations, native data shapes, pagination and examples. Results
retain native fields except credential fields (`api_key`, `access_token`,
`refresh_token`), which are removed recursively. Downloads stream to session files.
The connector does not add retries or fetch every page. Houston transport can
retry non-streamed HTTP 429 responses twice, including JSON or bodyless writes;
streamed forms, HTTP 5xx and transport failures are not automatically replayed.

Read-only is the default. Account/project discovery and inbox project/thread/content reads require
read-write: project objects can carry streaming keys, and opening inbox content
may mark messages read. Widget secret links and tipper exports also require
read-write, even where Tipeee uses GET. Publishing news may notify supporters or
collect tips; payouts transfer money and inbox broadcasts send messages. Use
these actions only when requested. Account security, provider agreements, KYC,
project publication/closure and Discord association remain on Tipeee's website.
