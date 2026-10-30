# Add Blockscout

Blockscout's explorers are public, so you need no account to start. Each
connection reads one chain.

1. In Houston, add the Blockscout connector.
2. Under **Chain**, choose the chain to read, such as Ethereum or Base.
3. Leave **Use a Blockscout API key** off, or turn it on and enter a key as
   described below.
4. Select **Add connector**.
5. Grant the appropriate members access to the connection.

To read another chain, add another Blockscout connection.

You can then ask about the chain, for example an address's balances and
recent transactions, what a transaction did, the largest holders of a token or
the source code of a verified contract.

## Advanced

### Add a Blockscout API key

Without a key, Houston reads the chain's public explorer, whose limits every
Houston user shares. Some explorers, such as those of Base, Arbitrum and
Polygon, can refuse these requests entirely. A free key gives your connection
its own limit of 5 requests per second and 100,000 credits a day (about 5,000
requests), and the same key works for every chain.

1. Sign in to the [Blockscout Developer Portal](https://dev.blockscout.com/),
   or create a free account. No credit card is needed.
2. Under **API keys**, select **Add new key**.
3. Enter a name, such as `Houston`, and leave the expiration date empty.
4. Select **Generate API key**, copy the key, which starts with `proapi_`, and
   select **Got it!**. The full key is shown only once.
5. In Houston, edit the Blockscout connection, turn on **Use a Blockscout API
   key**, paste the key into **Blockscout API key** and save.

If you regenerate or delete the key in the Developer Portal, update the
connection.

### Troubleshooting

- **"bot protection refused the request"**: this chain's public explorer
  refuses automated requests. Add an API key.
- **Requests are refused or slow**: the explorer limits how often it can be
  asked. Wait a moment and try again, or add an API key. With a key, check your
  remaining credits in the Developer Portal; the free plan's credits reset
  every day at midnight UTC.
- **The API key is refused**: it was mistyped, regenerated or has expired.
  Copy a current key from the Developer Portal.
- **A contract's source code is not found**: only contracts whose authors
  verified their source on Blockscout or Sourcify have one.
- See the [Blockscout API documentation](https://docs.blockscout.com/devs/apis)
  for how the data is organized.
