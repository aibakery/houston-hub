---
description: Look up customers, products, stock, orders, invoices, payments and bank accounts in your Dolibarr ERP and CRM, and create orders, invoices, payments and stock movements. Read-only access is guaranteed by a read-only Dolibarr user.
---

# Dolibarr

Connect your Dolibarr ERP and CRM so your agents can find customers, prospects,
suppliers and their contacts, check products, categories, warehouses, stock levels
and movements, and follow customer orders, commercial proposals, shipments and
invoices with their payments. They can also read supplier orders and invoices, bank
accounts, their transactions and balances.

With read and write access, agents can also create and edit third parties, contacts
and products, record stock movements, create orders and invoices with their lines,
turn an order into an invoice, validate orders and invoices, close orders and record
invoice payments. This makes Dolibarr a good back office for an online shop: agents
can copy yesterday's shop orders into Dolibarr, invoice them and keep stock in step.

**Read-only access depends on the Dolibarr user behind your API key.** Houston never
sends changes on a read-only connection, but Dolibarr has the final say on what a key
can do. For a read-only connection, use the key of a user who can only read, as the
setup guide describes.

The connection uses an API key from your own Dolibarr, and that user's permissions
still apply. Passwords and API keys are never shown to agents. Your key stays on
Houston's server.

Works with Dolibarr 16 or later, served over HTTPS at the root of a domain or in up
to two folders, such as `example.com/dolibarr`.

[Connect your Dolibarr](SETUP.md).
