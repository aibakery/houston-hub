# Connect AssessFirst

> Requires an Administrator with a Recruiter licence and API access. AssessFirst
> keeps one token per company; coordinate with other integrations before replacing it.

1. In [AssessFirst](https://app.assessfirst.com), open your profile's
   **Integration → AssessFirst API → Activate → Generate token**.
   If unavailable, ask your AssessFirst contact to enable API access.
2. Paste it into Houston's **API token** and choose **Production**.
3. Choose **Read-only**, **Completion status only** to hide scores and reports,
   or **Read and write** for invitations and changes. Save the connection and
   share it only with people allowed to see candidate data.

[Official token guide](https://help.assessfirst.com/en/knowledge/how-to-get-your-api-token).

## Advanced

- **Completion status only** still exposes names, email addresses, groups and
  predictive models. Group candidates in AssessFirst to track completion; the API
  has no campaigns. The token itself retains company-wide access.
- **Writes:** invitations send email. Obtain consent before adding a candidate
  without an invitation. Voice assessments and OnePager reports require their
  respective AssessFirst options.
- **Sandbox:** request access from [AssessFirst support](mailto:support@assessfirst.com),
  create a token at [simu.assessfirst.com](https://simu.assessfirst.com) and choose
  **Test**. Tokens work only in the environment where they were created.
