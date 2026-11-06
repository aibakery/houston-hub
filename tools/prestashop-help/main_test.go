package main

import (
	"context"
	"encoding/json"
	"github.com/aibakery/houston-hub/manifest"
	"github.com/aibakery/houston-hub/tools/conformance"
	"os"
	"strings"
	"testing"
)

func TestNativeFieldsAndPositionalInputs(t *testing.T) {
	directory := "../../connectors/prestashop/"
	raw, err := os.ReadFile(directory + "houston.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := manifest.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	modules := map[string]string{}
	for _, name := range []string{"connector.luau", "lib/help.luau", "lib/fields.luau"} {
		b, e := os.ReadFile(directory + name)
		if e != nil {
			t.Fatal(e)
		}
		modules[name] = string(b)
	}
	source := modules["connector.luau"]
	for _, tc := range []struct {
		name, operation, input string
		valid                  bool
	}{
		{"translated product", "createProduct", `{"fields":{"price":"12.00","name":[{"id":1,"value":"Mug"}],"associations":{"categories":[{"id":2}]}}}`, true},
		{"translated language ID", "createProduct", `{"fields":{"price":12,"name":[{"id":0,"value":"Mug"}]}}`, false},
		{"product required price", "createProduct", `{"fields":{"name":"Mug"}}`, false},
		{"partial product update", "updateProduct", `{"id":10,"fields":{"name":"Mug"}}`, true},
		{"clear associations", "updateProduct", `{"id":10,"fields":{"associations":{"categories":[]}}}`, true},
		{"association object", "updateProduct", `{"id":10,"fields":{"associations":{"categories":[2]}}}`, false},
		{"custom module field", "updateProduct", `{"id":10,"fields":{"custom_label":[{"id":1,"value":"Custom"}]}}`, true},
		{"XML controls", "updateProduct", `{"id":10,"fields":{"name":"bad\u0001value"}}`, false},
		{"XML forbidden codepoint", "updateProduct", `{"id":10,"fields":{"name":"bad\ufffevalue"}}`, false},
		{"XML markup text", "updateProduct", `{"id":10,"fields":{"description":"<p>Mug & cup</p>\n"}}`, true},
		{"native readonly quantity", "updateProduct", `{"id":10,"fields":{"quantity":12}}`, false},
		{"plain customer password", "createCustomer", `{"fields":{"firstname":"Ana","lastname":"Example","email":"ana@example.com","passwd":"replace-this-password"}}`, true},
		{"customer required password", "createCustomer", `{"fields":{"firstname":"Ana","lastname":"Example","email":"ana@example.com"}}`, false},
		{"customer password update", "updateCustomer", `{"id":6,"fields":{"passwd":"replace-this-password"}}`, false},
		{"customer secure key", "updateCustomer", `{"id":6,"fields":{"secure_key":"secret"}}`, false},
		{"native ID separate", "updateCustomer", `{"id":6,"fields":{"id":7}}`, false},
		{"stock negative quantity", "updateStockAvailable", `{"id":31,"fields":{"quantity":-2}}`, true},
		{"stock decimal quantity", "updateStockAvailable", `{"id":31,"fields":{"quantity":1.5}}`, false},
		{"status required order", "createOrderHistory", `{"fields":{"id_order_state":4}}`, false},
		{"email option", "createOrderHistory", `{"fields":{"id_order":123,"id_order_state":4},"opts":{"sendemail":true}}`, true},
		{"unsupported email option", "updateProduct", `{"id":10,"fields":{"active":true},"opts":{"sendemail":true}}`, false},
		{"native filters", "listOrders", `{"filter":{"current_state":[2,3],"date_upd":">[2026-10-01 00:00:00]"},"sort":["date_add_DESC","id_ASC"],"id_shop":"all","limit":100}`, true},
		{"filter exact delimiters", "listProducts", `{"filter":{"reference":["A|B"]}}`, false},
		{"secret filter", "listCustomers", `{"filter":{"secure_key":"secret"}}`, false},
		{"secret sort", "listCustomers", `{"sort":"passwd_DESC"}`, false},
		{"secret display", "listCustomers", `{"display":["passwd"]}`, false},
		{"page limit", "listProducts", `{"limit":101}`, false},
		{"path positive ID", "getProduct", `{"id":0}`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			name, _ := json.Marshal(tc.operation)
			modules["connector.luau"] = strings.Replace(source, "exports.help = function()", `functions[`+string(name)+`].inputSchema.examples={json.decode([====[`+tc.input+`]====])}`+"\nexports.help = function()", 1)
			fixture := `return {scenario={config={store_host="shop.example.com",access="read-write"},auth_method="key",auth_config={token="0123456789ABCDEF0123456789ABCDEF"}},run=function(c) assert(type(c[` + string(name) + `])=="function") end}`
			_, err := conformance.CheckCatalog(context.Background(), "", *m, modules, map[string]string{"schema.luau": fixture})
			if tc.valid && err != nil {
				t.Fatal(err)
			}
			if !tc.valid && (err == nil || !strings.Contains(err.Error(), "inputSchema.examples[0]")) {
				t.Fatalf("invalid input should fail schema validation: %v", err)
			}
		})
	}
}
