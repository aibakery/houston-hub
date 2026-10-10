---
description: Give agents SQL access to a MariaDB database, read-only unless you allow changes.
---
# MariaDB

Connect agents to a MariaDB database so they can answer questions from your data
with SQL.

## Explore your data

- Look up records, join tables, and summarize results.
- Inspect tables and columns to find the data a question needs.

## Make changes when you allow it

With **Read and write** access, agents can also insert, update, and delete rows
or change the schema. With **Read-only** access, every statement runs in a
read-only session and only reading statements are accepted, so data, schema and
server settings cannot change. Your database user's privileges always apply.
