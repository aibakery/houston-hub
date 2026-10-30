---
description: Read PostHog events, persons, insights and feature flags, and run SQL queries on your product analytics.
---

# PostHog

Connect PostHog so your agents can answer product questions from your analytics:
how many people signed up this week, which pages they visit, what a customer did
before contacting support, or which feature flags are rolled out and to whom.
They can browse your projects, recent events and persons, open your saved
insights, and run PostHog SQL (HogQL) queries for counts and trends.

Access is read-only: agents cannot capture events, change feature flags or edit
insights. They see only what your personal API key and your PostHog role allow,
and decrypted remote config payloads stay hidden. PostHog Cloud in the US and in
the EU is supported; self-hosted PostHog is not yet.

Queries count against PostHog's rate limits and your project's hourly query
budget, so agents favor a few targeted queries over large exports.

[Connect your PostHog account](SETUP.md).
