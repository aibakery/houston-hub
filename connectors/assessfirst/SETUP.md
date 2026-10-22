# Connect your AssessFirst account

You need an AssessFirst **Administrator** account that also has a **Recruiter**
licence, and API access on your AssessFirst subscription. No developer app is
required.

1. In AssessFirst, open your recruiter space at
   [app.assessfirst.com](https://app.assessfirst.com).
2. Select your picture or the unicorn icon at the top right, then
   **Integration**.
3. Select **AssessFirst API**, open **Activate**, and select **Generate token**.
   Copy the token. If the button is missing, your subscription may not include
   API access: ask your AssessFirst contact or write to
   [api@assessfirst.com](mailto:api@assessfirst.com).
4. In Houston, add the AssessFirst connector, shared with your organization or
   for yourself only. Paste the token into **API token** and keep **Access** set
   to **Read-only**.
5. Save the connection. For a shared connection, grant only the organization
   members who may see candidates' results.

You can then ask which candidates have finished their assessments, how well a
candidate fits a job, or for a candidate's summary report. Never paste the token
into a chat or saved action.

See AssessFirst's [How to get your API token](https://help.assessfirst.com/en/knowledge/how-to-get-your-api-token)
and [API documentation](https://documenter.getpostman.com/view/12154847/2sB2qWGjNX).

## Advanced

### Inviting candidates and other changes

Choose **Read and write** in Houston to let agents invite candidates, add
candidates, start voice assessments, manage groups and set up webhooks. The same
token works for both access levels: AssessFirst tokens have no separate
permissions, so **Read-only** is enforced by Houston.

Invitations are emailed by AssessFirst, at most once a day for the same address.
Adding a candidate without an invitation skips asking for their consent, so make
sure you already have it. Voice assessments need AssessFirst's Voice option, and
OnePager report links need AssessFirst to enable OnePager for your company.

### Token maintenance

AssessFirst keeps one API token per company. Generating a new token may stop
another integration that uses the current one, such as your applicant tracking
system: check with your AssessFirst administrator before you generate one, or
reuse the existing token. If requests start failing with "an error occured",
the token was probably replaced or revoked; update the connection's token.

AssessFirst allows about 100 API requests a minute.
