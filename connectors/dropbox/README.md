---
description: Find, read and organize your Dropbox files, shared links and file requests.
---

# Dropbox

Give your agents access to the files you keep in Dropbox, so they can find the
documents they need and keep your folders tidy.

- Browse and search folders, check file details and earlier versions, and follow
  recent changes.
- Download files, whole folders as zip archives, previews and thumbnails, and
  export Paper docs.
- Review shared links, shared folders and their members, files others shared with
  you, and your file requests.
- With **Read and write** access: upload files, create folders, rename, move,
  copy, delete and restore files, save files from the web, create and revoke
  shared links, share folders and files, and manage file requests.

Read-only access cannot change, share or delete your files. Deleted files stay
recoverable in Dropbox for your plan's retention period.

Choose **Custom folder access** to give each Houston connection its own folder
permissions, even when several connections use the same Dropbox account:

```json
{
  "/Finance": "read-only",
  "/Incoming": "read-write",
  "/Incoming/Approved": "read-only"
}
```

Unlisted folders are inaccessible. Each rule includes its subfolders; the most
specific rule wins. The example permits uploading into Incoming while protecting
Approved from changes, including moves or deletion of its parent. Houston callers
with read-only access cannot write even through a folder marked read-write.

Custom connections support folder browsing and search, file details and revisions,
downloads and exports, uploads, creating folders, copying, moving, deleting and
restoring files. Account information, sharing, file requests, batch operations and
background jobs are unavailable in this mode. Folder permissions are enforced by
Houston; Dropbox's OAuth permissions still cover the app's account access.

Available operations also follow the permissions granted by Dropbox. File transfers
use session files; uploads support up to 150 MiB per file.

[Connect your Dropbox account](SETUP.md).
