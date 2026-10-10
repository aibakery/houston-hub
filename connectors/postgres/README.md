---
description: Give agents SQL access to a PostgreSQL database, read-only unless you allow changes.
---
# PostgreSQL

Connect agents to a PostgreSQL database so they can answer questions from your
data with SQL.

## Explore your data

- Look up records, join tables, and summarize results.
- Inspect tables and columns to find the data a question needs.
- Read JSON columns as structured data.

## Make changes when you allow it

With **Read and write** access, agents can also insert, update, and delete rows
or change the schema. With **Read-only** access, every statement runs in a
read-only transaction, so data and schema cannot change. Your database user's permissions
always apply.
