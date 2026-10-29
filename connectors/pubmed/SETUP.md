# Add PubMed

PubMed is public, so you need no account, API key or developer app.

1. In Houston, add the PubMed connector. Leave **NCBI API key** empty, or enter
   a key as described below.
2. Select **Add connector**.
3. Grant the appropriate members access to the connection.

You can then ask about the literature, for example recent reviews on a topic,
the abstracts and MeSH terms of a paper, or the articles that cite it.

## Advanced

### Add an NCBI API key

Without a key, NCBI accepts 3 requests per second from all of Houston together,
so busy moments can slow requests down. A free key raises the limit to 10
requests per second for your connection.

1. Sign in to [NCBI](https://account.ncbi.nlm.nih.gov/), or create a free
   account.
2. Open your [account settings](https://account.ncbi.nlm.nih.gov/settings/).
3. Under **API Key Management**, select **Create an API Key** and copy the key.
4. In Houston, edit the PubMed connection, paste the key into **NCBI API key**
   and save.

An NCBI account has one key; creating a new one replaces the old key, so update
the connection when you do.

### Troubleshooting

- **Requests are refused or slow**: NCBI limits how often it can be asked. Wait
  a moment and try again, or add an API key.
- **"API key invalid"**: the key was mistyped or replaced. Copy it again from
  your NCBI account settings, or clear the field.
- **No full text for an article**: only articles in PMC's open-access subset
  and author manuscript collection have full text available. Others still have
  their abstract.
- **A search finds more than 9,999 articles**: PubMed returns only the first
  9,999 matches. Narrow the search, for example by date.
- See [PubMed help](https://pubmed.ncbi.nlm.nih.gov/help/) for the search
  syntax, and the [E-utilities documentation](https://www.ncbi.nlm.nih.gov/books/NBK25501/)
  for how the data is organized.
