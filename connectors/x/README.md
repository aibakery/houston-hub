---
description: Search public tweets, browse profiles, and follow conversations on X.
---

# X

Search and browse public tweets, profiles, user timelines, and mentions through
X API v2. Read recent or full-archive search results, look up individual tweets or
batches, and follow conversation IDs to find replies.

This connector uses an **app bearer token**, not a signed-in user's account.
It does not expose private account data, home feeds, bookmarks, direct messages,
or posting. Credentials stay on Houston and are injected only into GET requests
to the supported `api.x.com` endpoints.

## Usage

Call the connection's `help()` for the complete options and response contract.
All operations take one options object and return X's native response envelope:
`data`, `includes`, `meta`, and any partial `errors`. Keep tweet and user IDs as
strings. Read `note_post.text` when present for long-form posts.

```lua
local users = x.getUserByUsername({username = "XDevelopers"})
local tweets = x.listUserTweets({id = users.data.id, max_results = 10})
local matches = x.searchRecentTweets({query = "from:XDevelopers -is:retweet", max_results = 10})
-- For the next search page, pass matches.meta.next_token as next_token.
-- For timeline pages, pass tweets.meta.next_token as pagination_token.
```

Each call fetches one page without retries. Recent search covers the last seven
days; `searchAllTweets` uses the full archive when your developer account has
access. Request only the pages you need: X charges usage to your developer account.
Inspect partial errors even when a lookup returns some tweets successfully.

References: [search](https://docs.x.com/x-api/posts/search/introduction),
[lookup](https://docs.x.com/x-api/posts/lookup/quickstart),
[timelines](https://docs.x.com/x-api/posts/timelines/introduction), and
[profiles](https://docs.x.com/x-api/users/lookup/introduction).
