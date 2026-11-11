# Connect Fastmail

1. In Fastmail, open **Settings → Privacy & Security → Manage API tokens**.
2. Create an API token using the **JMAP** protocol. MCP and Dynamic DNS tokens
   are not supported.
3. Enable **Email**. Also enable **Email submission** if you want agents to send
   or reply, and **Masked Email** if you want to list masked addresses.
4. In Houston, choose the access level:
   - **Read-only** for browsing, searching, and downloading attachments.
   - **Read and draft** to also create, update, and delete drafts that you
     review and send yourself in Fastmail. Houston never sends with this level.
   - **Read and write** to also mark mail read/unread, send drafts, send, reply,
     create folders, move, archive, or delete mail.

   Drafts and other changes need a writable **Email** token; **Email submission**
   is only needed for sending. Leave it off so that even **Read and write** can
   prepare drafts but never send them.
5. Paste the token into **JMAP API token** and select **Add connection**.

API tokens require a Fastmail plan above Basic.

> Write access permits both moving mail to Trash and permanent deletion. Read and
> draft can permanently delete drafts only.
