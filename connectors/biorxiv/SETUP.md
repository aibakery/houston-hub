# Add bioRxiv and medRxiv

bioRxiv and medRxiv are public, so you need no account, API key or developer
app.

1. In Houston, add the bioRxiv and medRxiv connector and select **Add
   connector**. There are no settings to fill in.
2. Grant the appropriate members access to the connection.

You can then ask about preprints, for example the latest bioRxiv preprints on a
topic, what medRxiv published in epidemiology last week, or whether a preprint
has appeared in a journal.

## Advanced: troubleshooting

- **A preprint is not found**: bioRxiv and medRxiv DOIs both start with
  `10.1101/` (recent ones with `10.64898/`), so check that you asked the right
  server.
- **A PDF cannot be downloaded**: both websites limit automated downloads, and
  medRxiv currently blocks them. Open the PDF address in your browser instead,
  or try again after a few minutes for bioRxiv.
- **A recent preprint is missing from search**: search uses Europe PMC, which
  usually lists new preprints within a day. Listing a server's preprints for a
  date range shows them as soon as they are posted.
- **Listing a long period takes many requests**: bioRxiv posts several thousand
  preprints a month. Narrow the period or pick a category, or search instead.
- See the [bioRxiv and medRxiv API documentation](https://api.biorxiv.org) and
  [Europe PMC's search syntax](https://europepmc.org/searchsyntax) for how the
  data is organized.
