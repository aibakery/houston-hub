# Add Blockscout

1. Choose a **Chain** in Houston. Each connection reads one chain.
2. Leave **Use a Blockscout API key** off for public explorer access, or enable it
   and paste a key from the [Developer Portal](https://dev.blockscout.com/).
3. Select **Add connector** and share the connection with the members who need it.

> Some public explorers block automated requests. An API key gives your connection
> its own quota and works across chains.

## Advanced

In the Developer Portal, open **API keys → Add new key**, name it and select
**Generate API key**. Copy the `proapi_` value into **Blockscout API key** in Houston.
Update Houston after rotating the key; check remaining credits in the portal if
requests are refused.

[Blockscout API guide](https://docs.blockscout.com/devs/apis).
