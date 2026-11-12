# Umami

Explore website traffic, events, visitors, revenue, performance, errors, replays
and heatmaps. Manage websites, annotations, funnels, goals, segments, boards,
links, pixels, shares and teams. Administrative access also supports users,
account credentials and authentication policies. Send analytics and recordings
when collection writes are enabled.

Supports Umami Cloud (account region, US or EU) and public HTTPS self-hosted
Umami 3.4.1 installations. Older installations may not provide newer endpoints.
Your Umami role, subscription and enabled features still determine availability.

Connections default to **Read only** across all API areas. Choose **Custom** to select
several areas independently, granting each no access, read only, or read and
write. Unselected areas are disabled. Houston restricts both the callable
functions and outgoing API routes; these restrictions do not change the API key
inside Umami. Team inventory includes its websites, boards, links and pixels.
Account writes can issue credentials, and administration can change other users
and authentication policies. Collection writes accept the supplied website IDs;
custom access limits API areas, not individual websites or records.

Lists support filters and return one page at a time. Exports can be saved as ZIP
files in the execution session. Large date ranges and replays may require smaller
queries to stay within the response limit.

See [setup](SETUP.md) to connect an account and [API coverage](COVERAGE.md) for the
reviewed endpoint inventory. Callable details and examples are available through
the connection's `help()`.
