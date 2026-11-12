# Connect Slack

1. Choose **Read-only** or **Read and write** in Houston.
2. Select **Add to Slack**, sign in and check the workspace shown.
3. Select **Allow**. If approval is required, ask a workspace admin and reconnect
   after approval.

> Agents see what you can see, including private channels and direct messages.
> With write access, they post and share files under your name.

## Use Houston from Slackbot

Connecting Slack also adds Houston to Slackbot in that workspace. Open a direct
message with Slackbot, select **Apps**, then **+** next to Houston, and sign in
to Houston. Slackbot asks before each Houston action: choose **Allow once** or
**Always allow**. It stops waiting after 60 seconds, so ask for long work to run
in the background. To disconnect, remove Houston in Slackbot, or remove Slack
under **Your agents** in Houston's dashboard.

## Advanced

Add one connection per workspace; Enterprise Grid-wide installations are unsupported.
Reauthorize when changing access levels. Slack limits how fast apps outside its
Marketplace read channel history, so ask about a recent period rather than a
whole history.

Slack connections are personal: only the person who connected can use them, and
workspace admins can't share them. Each teammate connects their own account.

Deleting the Houston connection removes its saved authorization. Also revoke
Houston on Slack's [app management](https://slack.com/apps/manage) page to end
provider access. When you remove Houston in Slack, or your Slack account is
deactivated, Houston removes the connection within about a day.
