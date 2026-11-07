# Connect Attio

1. As a workspace admin, open **Workspace settings → Developers → New access token**.
2. Give the token **Read** scopes for the data agents need; leave write scopes off:

   | Data | Scopes |
   | --- | --- |
   | Records and objects | `record_permission`, `object_configuration` |
   | Lists | `list_entry`, `list_configuration` |
   | Notes, tasks, comments | `note`, `task`, `comment`; tasks also need `user_management` |
   | Members | `user_management` |
   | Meetings and transcripts | `meeting`, `call_recording` |
   | Files | `file` |
   | Email metadata | `email` (if enabled for your workspace) |

3. Save and copy the token, paste it into Houston's **API key**, and save.

[Official API key guide](https://attio.com/help/apps/other-apps/generating-an-api-key).

## Advanced

Edit the token's scopes from its menu on **Developers**; Houston uses the updated
permissions immediately. Email access may require Attio support to enable it.
If you delete the token, replace it in Houston. Keys are available on every plan.
