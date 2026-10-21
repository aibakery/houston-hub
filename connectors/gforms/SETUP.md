# Connect your Google account

1. Choose the access level:
   - **Read-only** to let agents read forms and their responses without
     changing anything.
   - **Read and write** to also let agents create forms, edit their questions
     and settings, and open or close them to responses.
2. Select **Connect with Google**, choose your account, and approve the
   permissions Google lists. If Google shows a checkbox per permission, tick
   them all: Houston refuses a partial grant.

Houston keeps your Google authorization on its server; agent scripts never see
it. The connection can open every form your Google account can edit, but nothing
else in your Drive; connecting Google Forms does not grant access to your other
Google services.

## Advanced: changing access and troubleshooting

- To change the access level, edit the connection and connect with Google again.
  Google then asks for the new set of permissions.
- To revoke access, remove the connection in Houston, or remove Houston from
  [your Google Account's third-party connections](https://myaccount.google.com/connections).
- Google Workspace administrators can block third-party apps. If Google refuses
  the connection, ask your administrator to allow Houston.
- An agent that cannot open a form may have been given its responder link (it
  contains `/forms/d/e/` and ends in `/viewform`) or a `forms.gle` short link.
  Share the edit link instead, from the address bar while editing the form.
- Older forms without Google's current publishing settings can be read and
  edited, but agents cannot open or close them to responses. Do that in Google
  Forms instead.
