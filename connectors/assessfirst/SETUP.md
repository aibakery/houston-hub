# Connect your AssessFirst account

You need an AssessFirst **Administrator** account that also has a **Recruiter**
licence, and API access on your AssessFirst subscription. No developer app is
required.

1. In AssessFirst, open your recruiter space at
   [app.assessfirst.com](https://app.assessfirst.com).
2. Select your picture or the unicorn icon at the top right, then
   **Integration** (**Integrations** in some accounts).
3. Select **AssessFirst API**, open **Activate**, and select **Generate token**.
   Copy the token. If the button is missing, your subscription may not include
   API access: ask your AssessFirst contact or write to
   [api@assessfirst.com](mailto:api@assessfirst.com).
4. In Houston, add the AssessFirst connector, shared with your organization or
   for yourself only. Paste the token into **API token** and keep **Environment**
   on **Production**. Keep **Access** set to **Read-only**, or choose
   [**Completion status only**](#completion-tracking-only) if agents should only
   see who has finished their assessments.
5. Save the connection. For a shared connection, grant only the organization
   members who may see candidates' results.

You can then ask which candidates have finished their assessments, how well a
candidate fits a job, or for a candidate's summary report. Never paste the token
into a chat or saved action.

See AssessFirst's [How to get your API token](https://help.assessfirst.com/en/knowledge/how-to-get-your-api-token)
and [API documentation](https://documenter.getpostman.com/view/12154847/2sB2qWGjNX).

## Advanced

### Completion tracking only

If agents only need to know who has finished their assessments, for example to
prepare reminders, set **Access** to **Completion status only**. Agents can then
list candidates, groups and predictive models, and see which assessments each
candidate has finished. Houston refuses every request for scores, written
syntheses, reports and fit with a job, and every change. Agents still see
candidates' names and email addresses.

AssessFirst's API has no campaigns: agents follow completion by candidate group
or against a predictive model, so put the candidates to follow in a group in
AssessFirst. Checking completion takes one request per candidate.

The token itself still has full access to your company's AssessFirst data: this
level limits what Houston requests with it.

### Inviting candidates and other changes

Choose **Read and write** in Houston to let agents invite candidates, add
candidates, start voice assessments, manage groups and set up webhooks. The same
token works at every access level: AssessFirst tokens have no separate
permissions, so the access level is enforced by Houston.

Invitations are emailed by AssessFirst, at most once a day for the same address.
Adding a candidate without an invitation skips asking for their consent, so make
sure you already have it. Voice assessments need AssessFirst's Voice option, and
OnePager report links need AssessFirst to enable OnePager for your company.

### Test environment

To try Houston with fictional candidates before connecting your production
account, ask [support@assessfirst.com](mailto:support@assessfirst.com) for a
sandbox on AssessFirst's test environment,
[simu.assessfirst.com](https://simu.assessfirst.com). Generate a token in its
recruiter space the same way, and set **Environment** to **Test**. A test token
only works with **Test**, and a production token only with **Production**.

### Token maintenance

AssessFirst keeps one API token per company. Generating a new token may stop
another integration that uses the current one, such as your applicant tracking
system: check with your AssessFirst administrator before you generate one, or
reuse the existing token. If requests start failing with "an error occured",
first check that **Environment** matches where the token was generated.
Otherwise the token was probably replaced or revoked; update the connection's
token.

AssessFirst allows about 100 API requests a minute.
