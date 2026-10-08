1. In Fastmail, open **Settings → Privacy & Security → Manage API tokens**.
2. Create an API token using the **JMAP** protocol. MCP and Dynamic DNS tokens
   are not supported.
3. Enable **Email**. Also enable **Email submission** if you want to send or reply,
   and **Masked Email** if you want to list masked addresses.
4. In Houston, choose the access level:
   - **Read-only** for browsing, searching, and downloading attachments.
   - **Read and write** to also send, reply, create folders, move, archive, or delete mail.
5. Paste the token into **JMAP API token** and select **Add connector**.

API tokens require a Fastmail plan above Basic. Your token stays on the Houston
server.
