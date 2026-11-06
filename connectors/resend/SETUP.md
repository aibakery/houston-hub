# Connect Resend

1. Open [API Keys](https://resend.com/api-keys), choose **Create API Key**, name it
   and select **Full access**. Copy the `re_` key.
2. Paste it into Houston's **API key**, choose **Read-only** or **Read and write**,
   and save.
3. To send beyond your own address, verify a sending domain under
   [Domains](https://resend.com/domains).

> Full access keys cover your whole Resend team. Writes can send email, broadcasts
> and automations to real people. Houston requires write access to expose webhook
> secrets and full API logs too.

[Official API key guide](https://resend.com/docs/dashboard/api-keys/introduction).

## Advanced

**Sending access** keys, optionally restricted to one domain, work only for sending
on a **Read and write** connection; reads fail. Inboxes need receiving enabled on
their domain and may require forwarding. Your plan's inbox and sending limits apply.
Replace revoked keys in Houston; manage keys and OAuth apps in Resend.
