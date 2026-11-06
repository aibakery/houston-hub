# Connect RevenueCat

1. As a project Admin, open **API keys → New secret API key** in
   [RevenueCat](https://app.revenuecat.com). Select **V2**.
2. Grant the permissions below, then generate and copy the `sk_` key.
3. In Houston, paste **Secret API key (v2)**, choose the matching access level and save.

| Permission | Read-only | Read and write |
| --- | --- | --- |
| Charts & metrics | Read only | Read only |
| Customer information | Read only | Read & write |
| Project configuration | Read only | Read & write |

[Official API key guide](https://www.revenuecat.com/docs/projects/authentication).

## Advanced

Use one key and connection per project; v1 and public SDK keys are unsupported.
If per-resource permissions are available, grant writes only to customers,
offerings and packages; projects, apps, products, entitlements, subscriptions,
purchases and overview metrics need only reads. Houston permits promotional
entitlement and offering changes, not refunds or subscription cancellation.

Create a replacement key when permissions are missing or the old key is revoked.
