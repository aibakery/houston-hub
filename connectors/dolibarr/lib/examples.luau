-- Authored native positional-call examples; fixtures execute every example.
return json.decode([====[
{
	"addInvoiceLine": [
		{
			"fields": {
				"fk_product": 9,
				"qty": 1,
				"subprice": "12.50",
				"tva_tx": "20"
			},
			"id": 12
		}
	],
	"addInvoicePayment": [
		{
			"fields": {
				"accountid": 1,
				"closepaidinvoices": "yes",
				"datepaye": 1794873600,
				"num_payment": "TRANSFER-1042",
				"paymentid": 1
			},
			"id": 12
		}
	],
	"addOrderLine": [
		{
			"fields": {
				"desc": "Shipping",
				"product_type": 1,
				"qty": 1,
				"subprice": "5.00",
				"tva_tx": "20"
			},
			"id": 12
		}
	],
	"closeOrder": [
		{
			"id": 12
		}
	],
	"createContact": [
		{
			"fields": {
				"email": "ana@example.com",
				"firstname": "Ana",
				"lastname": "Example",
				"socid": 12
			}
		}
	],
	"createInvoice": [
		{
			"fields": {
				"date": 1794873600,
				"lines": [
					{
						"fk_product": 9,
						"qty": 2,
						"subprice": "12.50",
						"tva_tx": "20"
					}
				],
				"ref_ext": "WEB-1042",
				"socid": 12
			}
		}
	],
	"createInvoiceFromOrder": [
		{
			"id": 12
		}
	],
	"createOrder": [
		{
			"fields": {
				"date": 1794873600,
				"lines": [
					{
						"fk_product": 9,
						"qty": 2,
						"subprice": "12.50",
						"tva_tx": "20"
					}
				],
				"ref_ext": "WEB-1042",
				"socid": 12
			}
		}
	],
	"createProduct": [
		{
			"fields": {
				"label": "Art print",
				"price": "12.50",
				"price_base_type": "HT",
				"ref": "PRINT-01",
				"status": 1,
				"status_buy": 1,
				"tva_tx": "20",
				"type": 0
			}
		}
	],
	"createStockMovement": [
		{
			"fields": {
				"label": "Order WEB-1042",
				"product_id": 9,
				"qty": -2,
				"warehouse_id": 1
			}
		}
	],
	"createThirdparty": [
		{
			"fields": {
				"array_options": {
					"options_shop": "online"
				},
				"client": 1,
				"country_id": 1,
				"email": "ana@example.com",
				"name": "Example Studio"
			}
		}
	],
	"getBankAccount": [
		{
			"id": 12
		}
	],
	"getBankAccountBalance": [
		{
			"id": 12
		}
	],
	"getCategory": [
		{
			"id": 12
		}
	],
	"getContact": [
		{
			"id": 12
		}
	],
	"getInvoice": [
		{
			"id": 12
		},
		{
			"id": "42"
		}
	],
	"getOrder": [
		{
			"id": 12
		}
	],
	"getProduct": [
		{
			"id": 12,
			"opts": {
				"includestockdata": true
			}
		}
	],
	"getProductStock": [
		{
			"id": 12,
			"opts": {
				"selected_warehouse_id": 1
			}
		}
	],
	"getProposal": [
		{
			"id": 12
		}
	],
	"getShipment": [
		{
			"id": 12
		}
	],
	"getStatus": [
		{}
	],
	"getSupplierInvoice": [
		{
			"id": 12
		}
	],
	"getSupplierOrder": [
		{
			"id": 12
		}
	],
	"getThirdparty": [
		{
			"id": 12
		}
	],
	"getWarehouse": [
		{
			"id": 12
		}
	],
	"listBankAccountLines": [
		{
			"id": 12,
			"opts": {
				"sqlfilters": "(dateo:\u003e=:'2026-11-01')"
			}
		}
	],
	"listBankAccounts": [
		{
			"opts": {
				"limit": 20,
				"page": 0,
				"sortorder": "DESC"
			}
		}
	],
	"listCategories": [
		{
			"opts": {
				"limit": 20,
				"page": 0,
				"type": "product"
			}
		}
	],
	"listContacts": [
		{
			"opts": {
				"limit": 20,
				"page": 0,
				"sortorder": "DESC"
			}
		}
	],
	"listInvoicePayments": [
		{
			"id": 12
		}
	],
	"listInvoices": [
		{
			"opts": {
				"limit": 20,
				"page": 0,
				"status": "unpaid",
				"thirdparty_ids": [
					12,
					"13"
				]
			}
		}
	],
	"listOrders": [
		{
			"opts": {
				"limit": 20,
				"page": 0,
				"sortorder": "DESC"
			}
		}
	],
	"listPaymentTypes": [
		{
			"opts": {
				"limit": 20,
				"page": 0,
				"sortorder": "DESC"
			}
		}
	],
	"listProducts": [
		{
			"opts": {
				"limit": 20,
				"mode": 1,
				"page": 0,
				"properties": [
					"id",
					"ref",
					"label",
					"price"
				]
			}
		}
	],
	"listProposals": [
		{
			"opts": {
				"limit": 20,
				"page": 0,
				"sortorder": "DESC"
			}
		}
	],
	"listShipments": [
		{
			"opts": {
				"limit": 20,
				"page": 0,
				"sortorder": "DESC"
			}
		}
	],
	"listStockMovements": [
		{
			"opts": {
				"limit": 20,
				"page": 0,
				"sortorder": "DESC"
			}
		}
	],
	"listSupplierInvoicePayments": [
		{
			"id": 12
		}
	],
	"listSupplierInvoices": [
		{
			"opts": {
				"limit": 20,
				"page": 0,
				"sortorder": "DESC"
			}
		}
	],
	"listSupplierOrders": [
		{
			"opts": {
				"limit": 20,
				"page": 0,
				"sortorder": "DESC"
			}
		}
	],
	"listThirdparties": [
		{
			"opts": {
				"limit": 20,
				"mode": 1,
				"page": 0,
				"sqlfilters": "(t.email:=:'ana@example.com')"
			}
		}
	],
	"listWarehouses": [
		{
			"opts": {
				"limit": 20,
				"page": 0,
				"sortorder": "DESC"
			}
		}
	],
	"updateContact": [
		{
			"fields": {
				"poste": "Designer"
			},
			"id": 12
		}
	],
	"updateProduct": [
		{
			"fields": {
				"description": "A signed art print",
				"price": "15.00"
			},
			"id": 12
		}
	],
	"updateThirdparty": [
		{
			"fields": {
				"name_alias": "Studio",
				"phone": "+33155550123"
			},
			"id": 12
		}
	],
	"validateInvoice": [
		{
			"id": 12
		},
		{
			"fields": {
				"idwarehouse": 1
			},
			"id": 12
		}
	],
	"validateOrder": [
		{
			"fields": {
				"idwarehouse": 1,
				"notrigger": 0
			},
			"id": 12
		}
	]
}
]====])
