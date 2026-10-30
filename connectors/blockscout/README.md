---
description: Read addresses, balances, transactions, blocks, tokens and verified smart contracts on Ethereum, Base, Arbitrum and other chains through Blockscout.
---

# Blockscout

Let agents read public blockchain data from Blockscout, the open-source block
explorer behind Ethereum, Base, OP Mainnet, Arbitrum, Gnosis, Polygon, Celo,
Scroll, ZKsync and many other chains, including their test networks.

## Follow addresses

- Read an address's native balance, ENS name, tags and activity counts.
- List its token balances and NFTs.
- List the transactions it sent or received, its token transfers, the internal
  calls made by contracts and the events its contract emitted.
- See how its balance changed over time.

## Inspect transactions and blocks

- Read a transaction's status, value, fee, called function and decoded
  arguments, with its event logs, token transfers and internal calls.
- Get a plain-language summary of what a transaction did.
- Read the latest blocks and transactions, or any block by number or hash.

## Explore tokens and contracts

- Search tokens, read their supply, price and holder counts, and list their
  holders and transfers.
- Read NFT collections and the metadata of each NFT.
- Read the source code and ABI of verified smart contracts, and list recently
  verified contracts.
- Search the chain for names, symbols, addresses and hashes, and read its
  statistics such as gas prices.

Each connection reads one chain; add a connection for each chain you follow.
Access is read-only: the connector can't sign or send transactions. Public
explorers need no account, but they share their limits with every Houston user
and some refuse automated requests. A free Blockscout API key gives your
connection its own limit and works on every chain. This connector is not
affiliated with or endorsed by Blockscout.

[Add Blockscout](SETUP.md).
