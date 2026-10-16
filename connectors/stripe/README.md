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

Functions return one page at a time. Read-only results remove payment-capable
credential fields (`client_secret`, `confirmation_secret`, `client_token` and
`secret`) at every depth, including metadata. Other fields and read-write results
preserve Stripe's native values. Hosted payment links remain sensitive. File
uploads and downloads stream through Houston session files. Call `help()` for
available operations, parameters, pagination and examples.

This connector uses Stripe's public payments and billing API, pinned to
`2026-09-30.endive`. It does not manage Atlas incorporation, equity, tax filings
or incorporation documents. Those remain in the [Atlas
Dashboard](https://dashboard.stripe.com/atlas). Stripe's public API does not document
a self-service Atlas interface; a partner integration would need separate access.
