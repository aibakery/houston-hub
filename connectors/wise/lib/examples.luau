-- Reviewed examples for the connector's legacy Wise endpoints. IDs refer to resources in the selected profile.
return json.decode([====[
{
	"cancelTransfer": [
		{
			"transferId": 101
		}
	],
	"createBalance": [
		{
			"currency": "EUR",
			"idempotenceUuid": "00000000-0000-4000-8000-000000000002",
			"profileId": 101,
			"type": "STANDARD"
		},
		{
			"currency": "EUR",
			"idempotenceUuid": "00000000-0000-4000-8000-000000000002",
			"name": "Tax reserve",
			"profileId": 101,
			"type": "SAVINGS"
		}
	],
	"createBalanceMovement": [
		{
			"idempotenceUuid": "00000000-0000-4000-8000-000000000002",
			"profileId": 101,
			"quoteId": "00000000-0000-4000-8000-000000000001"
		},
		{
			"amount": {
				"currency": "GBP",
				"value": 25
			},
			"idempotenceUuid": "00000000-0000-4000-8000-000000000002",
			"profileId": 101,
			"sourceBalanceId": 101,
			"targetBalanceId": 102
		}
	],
	"createBatchGroup": [
		{
			"name": "November invoices",
			"profileId": 101,
			"sourceCurrency": "GBP"
		}
	],
	"createBatchTransfer": [
		{
			"batchGroupId": "00000000-0000-4000-8000-000000000001",
			"customerTransactionId": "00000000-0000-4000-8000-000000000002",
			"details": {
				"reference": "Invoice 1041"
			},
			"profileId": 101,
			"quoteUuid": "00000000-0000-4000-8000-000000000001",
			"targetAccount": 201
		}
	],
	"createQuote": [
		{
			"preferredPayIn": "BALANCE",
			"profileId": 101,
			"sourceAmount": 100,
			"sourceCurrency": "GBP",
			"targetCurrency": "EUR"
		},
		{
			"preferredPayIn": "BALANCE",
			"profileId": 101,
			"sourceAmount": null,
			"sourceCurrency": "GBP",
			"targetAmount": 100,
			"targetCurrency": "EUR"
		}
	],
	"createRecipient": [
		{
			"accountHolderName": "Ana Example",
			"currency": "GBP",
			"details": {
				"accountNumber": "37778842",
				"legalType": "PRIVATE",
				"sortCode": "040075"
			},
			"ownedByCustomer": false,
			"profile": 101,
			"type": "sort_code"
		}
	],
	"createTransfer": [
		{
			"customerTransactionId": "00000000-0000-4000-8000-000000000002",
			"details": {
				"reference": "Invoice 1041"
			},
			"quoteUuid": "00000000-0000-4000-8000-000000000001",
			"targetAccount": 201
		}
	],
	"deleteBalance": [
		{
			"balanceId": 101,
			"profileId": 101
		}
	],
	"downloadBalanceStatement": [
		{
			"balanceId": 101,
			"currency": "GBP",
			"format": "pdf",
			"intervalEnd": "2026-10-31T23:59:59Z",
			"intervalStart": "2026-10-01T00:00:00Z",
			"path": "downloadBalanceStatement.pdf",
			"profileId": 101,
			"type": "COMPACT"
		}
	],
	"downloadTransferReceipt": [
		{
			"path": "downloadTransferReceipt.pdf",
			"transferId": 101
		}
	],
	"fundBatchGroup": [
		{
			"batchGroupId": "00000000-0000-4000-8000-000000000001",
			"profileId": 101,
			"type": "BALANCE"
		}
	],
	"fundTransfer": [
		{
			"profileId": 101,
			"transferId": 101,
			"type": "BALANCE"
		}
	],
	"getAccountRequirements": [
		{
			"addressRequired": true,
			"originatorLegalEntityType": "PRIVATE",
			"quoteId": "00000000-0000-4000-8000-000000000001"
		}
	],
	"getBalance": [
		{
			"balanceId": 101,
			"profileId": 101
		}
	],
	"getBalanceStatement": [
		{
			"balanceId": 101,
			"currency": "GBP",
			"intervalEnd": "2026-10-31T23:59:59Z",
			"intervalStart": "2026-10-01T00:00:00Z",
			"profileId": 101,
			"type": "COMPACT"
		}
	],
	"getBatchGroup": [
		{
			"batchGroupId": "00000000-0000-4000-8000-000000000001",
			"profileId": 101
		}
	],
	"getMe": [
		{}
	],
	"getProfile": [
		{
			"profileId": 101
		}
	],
	"getQuote": [
		{
			"profileId": 101,
			"quoteId": "00000000-0000-4000-8000-000000000001"
		}
	],
	"getRates": [
		{
			"source": "GBP",
			"target": "EUR"
		}
	],
	"getRecipient": [
		{
			"accountId": 101
		}
	],
	"getTotalFunds": [
		{
			"currency": "GBP",
			"profileId": 101
		}
	],
	"getTransfer": [
		{
			"transferId": 101
		}
	],
	"listAccountDetails": [
		{
			"profileId": 101
		}
	],
	"listActivities": [
		{
			"profileId": 101,
			"size": 20,
			"status": "COMPLETED"
		}
	],
	"listBalances": [
		{
			"profileId": 101,
			"types": [
				"STANDARD",
				"SAVINGS"
			]
		}
	],
	"listCurrencies": [
		{}
	],
	"listProfiles": [
		{}
	],
	"listRecipients": [
		{
			"active": true,
			"profileId": 101,
			"size": 20
		}
	],
	"listTransfers": [
		{
			"limit": 20,
			"offset": 0,
			"profile": 101
		}
	],
	"refreshAccountRequirements": [
		{
			"accountHolderName": "Ana Example",
			"currency": "GBP",
			"details": {
				"legalType": "PRIVATE"
			},
			"originatorLegalEntityType": "PRIVATE",
			"profile": 101,
			"quoteId": "00000000-0000-4000-8000-000000000001",
			"type": "sort_code"
		}
	],
	"updateBatchGroup": [
		{
			"batchGroupId": "00000000-0000-4000-8000-000000000001",
			"profileId": 101,
			"status": "COMPLETED",
			"version": 1
		}
	],
	"updateQuote": [
		{
			"payOut": "BANK_TRANSFER",
			"profileId": 101,
			"quoteId": "00000000-0000-4000-8000-000000000001",
			"targetAccount": 201
		}
	],
	"validateTransferRequirements": [
		{
			"quoteUuid": "00000000-0000-4000-8000-000000000001",
			"targetAccount": 201
		}
	]
}
]====])
