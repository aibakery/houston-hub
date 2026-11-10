# Connect Fastmail

1. In Fastmail, open **Settings → Privacy & Security → Manage API tokens**.
2. Create an API token using the **JMAP** protocol. MCP and Dynamic DNS tokens
   are not supported.
3. Enable **Email**. Also enable **Email submission** if you want agents to send
   or reply, and **Masked Email** if you want to list masked addresses. Leave
   **Email submission** off to let agents prepare drafts that only you can send.
4. In Houston, choose the access level:
   - **Read-only** for browsing, searching, and downloading attachments.
   - **Read and write** to also mark mail read/unread, prepare drafts, send,
     reply, create folders, move, archive, or delete mail. Changing mail needs a
     writable **Email** token; **Email submission** is only needed for sending.
5. Paste the token into **JMAP API token** and select **Add connection**.

API tokens require a Fastmail plan above Basic.

> Write access permits both moving mail to Trash and permanent deletion.
