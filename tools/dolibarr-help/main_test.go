package main

import (
	"context"
	"encoding/json"
	"os"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
	"github.com/aibakery/houston-hub/tools/conformance"
)

func TestNativeSchemasAndConnectorTransport(t *testing.T) {

	modules := map[string]string{}
	for _, name := range []string{"connector.luau", "lib/help.luau", "lib/examples.luau"} {
		b, err := os.ReadFile("../../connectors/dolibarr/" + name)
		if err != nil {
			t.Fatal(err)
		}
		modules[name] = string(b)
	}
	source := modules["connector.luau"]
	raw, err := os.ReadFile("../../connectors/dolibarr/houston.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := manifest.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, operation, input string
		valid                  bool
	}{

		{"numeric path", "getInvoice", "{\"id\":42}", true},
		{"digit string path", "getInvoice", "{\"id\":\"9007199254740991\"}", true},
		{"unsafe numeric ID", "getInvoice", "{\"id\":9007199254740992}", false},
		{"unsafe string ID", "getInvoice", "{\"id\":\"9007199254740992\"}", false},
		{"ID leading zero", "getInvoice", "{\"id\":\"042\"}", false},
		{"zero ID", "getInvoice", "{\"id\":0}", false},
		{"list upper limit", "listInvoices", "{\"opts\":{\"limit\":200,\"page\":0}}", true},
		{"unbounded list rejected", "listInvoices", "{\"opts\":{\"limit\":0}}", false},
		{"list limit overflow", "listInvoices", "{\"opts\":{\"limit\":201}}", false},
		{"query null", "listInvoices", "{\"opts\":{\"status\":null}}", false},
		{"native enum case", "listInvoices", "{\"opts\":{\"status\":\"UNPAID\"}}", false},
		{"ID list", "listInvoices", "{\"opts\":{\"thirdparty_ids\":[12,\"13\"]}}", true},
		{"empty ID list", "listInvoices", "{\"opts\":{\"thirdparty_ids\":[]}}", false},
		{"empty properties", "listProducts", "{\"opts\":{\"properties\":[]}}", false},
		{"bank filter required", "listBankAccountLines", "{\"id\":1}", false},
		{"secret sort column", "listThirdparties", "{\"opts\":{\"sortfield\":\"t.API_KEY\"}}", false},
		{"secret SQL column", "listThirdparties", "{\"opts\":{\"sqlfilters\":\"(t.webservices_key:like:'a%')\"}}", false},
		{"legacy sanitized secret column", "listThirdparties", "{\"opts\":{\"sqlfilters\":\"(t.WEB#SERVICES_KEY:like:'a%')\"}}", false},
		{"secret word in SQL value", "listThirdparties", "{\"opts\":{\"sqlfilters\":\"(t.name:like:'webservices_key')\"}}", true},
		{"native nested line", "createOrder", "{\"fields\":{\"socid\":12,\"date\":1794873600,\"lines\":[{\"fk_product\":9,\"qty\":2,\"subprice\":\"12.50\"}]}}", true},
		{"native nested quantity type", "createOrder", "{\"fields\":{\"socid\":12,\"date\":1794873600,\"lines\":[{\"fk_product\":9,\"qty\":\"two\"}]}}", false},
		{"thirdparty create name", "createThirdparty", "{\"fields\":{\"email\":\"ana@example.com\"}}", false},
		{"update nonempty fields", "updateThirdparty", "{\"id\":12,\"fields\":{}}", false},
		{"body cannot replace ID", "updateThirdparty", "{\"id\":12,\"fields\":{\"id\":13,\"name\":\"Example\"}}", false},
		{"custom native field", "updateThirdparty", "{\"id\":12,\"fields\":{\"array_options\":{\"options_shop\":\"online\"}}}", true},
		{"custom field namespace", "updateThirdparty", "{\"id\":12,\"fields\":{\"array_options\":{\"shop\":\"online\"}}}", false},
		{"optional action body", "validateOrder", "{\"id\":12}", true},
		{"payment close flag", "addInvoicePayment", "{\"id\":12,\"fields\":{\"datepaye\":1794873600,\"paymentid\":1,\"accountid\":1,\"closepaidinvoices\":true}}", false},
		{"negative stock movement", "createStockMovement", "{\"fields\":{\"product_id\":9,\"warehouse_id\":1,\"qty\":-2,\"label\":\"Order\"}}", true},
		{"legacy stock aliases", "createStockMovement", "{\"fields\":{\"product_id\":9,\"warehouse_id\":1,\"qty\":2,\"movementlabel\":\"Receipt\",\"lot\":\"BATCH-1\",\"dlc\":\"2027-01-01\"}}", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			operation, _ := json.Marshal(tc.operation)

			modules["connector.luau"] = source[:strings.LastIndex(source, "return exports")] + `local schema=docs[` + string(operation) + `].inputSchema;schema.examples={json.decode([====[` + tc.input + `]====])};return {invoke=function(input) return input end,help={text="Schema fixture",functions={invoke={description="Native input",inputSchema=schema}}}}`
			_, err := conformance.CheckCatalog(context.Background(), "", *m, modules, map[string]string{"example.luau": `return {scenario={config={host="erp.example.com",access="read-write"},auth_method="key",auth_config={token="fixture-token"}},run=function(c) assert(type(fixture.example("invoke"))=="table") end}`})
			if tc.valid && err != nil {
				t.Fatal(err)
			}
			if !tc.valid && (err == nil || !strings.Contains(err.Error(), "inputSchema.examples[0]")) {
				t.Fatalf("invalid input should fail schema validation: %v", err)
			}
		})
	}
}
