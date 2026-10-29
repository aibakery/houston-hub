# Add ChEMBL

ChEMBL is public, so you need no account, API key or developer app.

1. In Houston, add the ChEMBL connector and select **Add connector**. There are
   no settings to fill in.
2. Grant the appropriate members access to the connection.

You can then ask about molecules and drugs, for example the approved drugs
similar to a structure, or the most potent compounds measured against a protein.

## Advanced: troubleshooting

- **A molecule or target is not found**: ChEMBL identifies records by ChEMBL
  IDs such as `CHEMBL25` (aspirin). Search by name first when you don't know
  the ID.
- **A structure search fails**: check that the SMILES string is valid. A
  substructure needs at least five characters.
- **Requests are slow or time out**: ChEMBL can take several seconds to answer
  a new question, and caches the answer. Try again, or ask a narrower question.
- See the [ChEMBL web services documentation](https://chembl.gitbook.io/chembl-interface-documentation/web-services/chembl-data-web-services)
  for how its data is organized.
