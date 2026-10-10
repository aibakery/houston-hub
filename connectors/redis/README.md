---
description: Give agents access to Redis keys, hashes, lists, and streams, read-only unless you allow changes.
---
# Redis

Connect agents to Redis so they can inspect cached values, queues, counters, and
streams.

## Look into your data

- Read strings, hashes, lists, sets, sorted sets, and streams.
- Scan keys by pattern and check their types and expiry.
- Use read-only commands from Redis modules, such as JSON and time series.

## Make changes when you allow it

With **Read and write** access, agents can also set, update, and delete keys.
With **Read-only** access, agents can run only the commands Redis marks as
read-only. Your Redis user's ACL always applies.
