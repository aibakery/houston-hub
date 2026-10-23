# Connect Tipeee

1. Sign in to your creator account at [Tipeee](https://en.tipeee.com/) and open
   your creator dashboard.
2. Open your browser's developer tools. In Chrome or Edge, go to
   **Application → Cookies** and select the Tipeee site. In Firefox, use
   **Storage → Cookies**. Find the cookie named **auth** and copy its value.
3. In Houston, choose **Website session** and paste the value into
   **Tipeee session token**. Keep it private, just like a password.
4. Choose **Read-only** to view content and reports, or **Read and write** to
   manage your page, use your inbox, send messages or request payouts. Save
   the connection.

## Advanced

If you cannot find the **auth** cookie, check **Local Storage** for your Tipeee
site and look for **access_token**. Copy its value without surrounding quotes.
You can also reload your signed-in dashboard with the **Network** panel open,
select a request to **api.tipeee.com**, and copy the **access_token** query value.
Copy only the value, not the whole URL.

You do not need a developer application or a streaming API key. The streaming
key shown in Tipeee's widget settings is for a different feature.

Houston saves the token, but Tipeee can expire or revoke it. The website cookie's
expiry date does not tell us how long the saved token will work. Automatic
renewal is not available for this connection. If access stops working, sign in
again and update the token in Houston.

If a particular page or report is unavailable, check that the connected account
owns the page and has the necessary Tipeee permissions. Payouts also require
Tipeee's identity verification and payout setup.
