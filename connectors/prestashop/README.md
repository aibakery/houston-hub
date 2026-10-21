---
description: Check orders, customers, products and stock in your PrestaShop store, and update order statuses, tracking numbers, stock and products. Read-only access requires a view-only PrestaShop key.
---

# PrestaShop

Connect your PrestaShop store so your agents can look up orders, their lines,
status history, invoices, payments and shipments, find customers and their
addresses and carts, and check products, combinations, categories, stock, brands,
suppliers, carriers and vouchers.

With read and write access, agents can also change an order's status, set a
shipment's tracking number, adjust stock quantities, and create, edit or delete
products and customers. Status changes and tracking numbers can email your
customers when agents ask for it.

**Read-only access depends on the key you create in PrestaShop.** PrestaShop, not
Houston, has the final say on what a key can change: Houston never sends changes
on a read-only connection, but a key allowed to edit or delete can still change
your store. For a read-only connection, use a key that can only view, as the
setup guide describes.

The connection uses a webservice key from your own store, and the key's other
permissions still apply. Customer password hashes and private order keys are
never shown to agents. Your key stays on Houston's server.

Works with PrestaShop 1.7, 8 and 9. Editing existing records needs PrestaShop 8 or
later.

[Connect your PrestaShop store](SETUP.md).
