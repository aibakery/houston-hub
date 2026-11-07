# Connect Dolibarr

Requires Dolibarr 16 or later over HTTPS and an administrator to enable the API.

> For read-only access, use a non-admin user's key with only read permissions.
> Dolibarr administrators bypass most permission checks.

1. Enable **API / Web services (REST server)** under **Setup → Modules/Applications**.
2. Create a non-admin, non-external `houston` user under **Users & Groups**.
   Grant read permissions for the modules agents need. Add **Extend access to all
   third parties AND their objects** only if agents should see all third parties;
   otherwise access is limited to the user's assigned ones.
3. On the user's card, choose **Modify** and generate **Token for API**
   (**Key for API** before version 23). Save and copy it.
4. In Houston, enter **Dolibarr domain** without `https://` or a path. Put a folder
   such as `/dolibarr` in **Install path**. Paste **API key**, choose **Read-only**
   and save.

[Official REST API guide](https://wiki.dolibarr.org/index.php/Module_Web_Services_API_REST_(developer)).

## Advanced

### Changes

Use a separate key and **Read and write** connection. Grant create/modify
permissions only for the relevant modules. Stock changes require **Create/modify
warehouses**; invoice payments require **Create payments for customer invoices**
(version 24+) or **Create/modify customer invoices** on earlier versions. With
advanced permissions, also grant order/invoice validation. Validation assigns
final numbers and may send notifications. Agents cannot delete records.

### Connection problems

The API must answer at `https://<domain><install path>/api/index.php/status`.
Use the final HTTPS domain; redirects and install paths deeper than two folders
are unsupported. Check enabled modules, user permissions and API IP restrictions.
Before version 20, missing permissions can return 401. Multicompany access uses
the key owner's entity.
