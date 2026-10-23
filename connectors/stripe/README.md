---
description: Read and manage Stripe customers, payments, billing, balances and files.
---
# Stripe

Connect a Stripe restricted or secret API key to work with customers, products,
prices, payment intents, charges, refunds, subscriptions, invoices, payment methods,
balances, payouts, disputes, events, Checkout sessions and files.

Read-only is the default. Read and write adds customer and catalog changes,
payment confirmation and capture, refunds, subscription changes, invoice actions,
payouts, Checkout and billing portal sessions, and file uploads. Stripe key
permissions and account eligibility also apply. Keys select live or test data.

Read-only access hides credentials that could authorize payments. Payment links
can still allow someone to complete a payment, so share them carefully. You can
also download files and, with read and write access, upload them.

This connector uses Stripe's public payments and billing API, pinned to
`2026-09-30.endive`. It does not manage Atlas incorporation, equity, tax filings
or incorporation documents. Those remain in the [Atlas
Dashboard](https://dashboard.stripe.com/atlas). Stripe's public API does not document
a self-service Atlas interface; a partner integration would need separate access.
