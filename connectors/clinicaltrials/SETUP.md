# Add ClinicalTrials.gov

ClinicalTrials.gov is public, so you need no account, API key or developer app.

1. In Houston, add the ClinicalTrials.gov connector and select **Add connector**.
   There are no settings to fill in.
2. Grant the appropriate members access to the connection.

You can then ask about studies, for example recruiting phase 3 trials for a
condition near a city, or the posted results of a study by its NCT number.

## Advanced: troubleshooting

- **A study ID is not found**: ClinicalTrials.gov identifies studies by an NCT
  number, `NCT` followed by eight digits, such as `NCT04368728`. Some older
  numbers were merged into another study; the error then names the current
  number.
- **Requests are refused or slow**: ClinicalTrials.gov may refuse requests that
  arrive too quickly. Wait a minute and try again with fewer, broader
  requests.
- See the [ClinicalTrials.gov API documentation](https://clinicaltrials.gov/data-api/about-api)
  for how its search and data work.
