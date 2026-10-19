package main

import (
	"net/http"
	"slices"
	"strings"
	"testing"

	"github.com/aibakery/houston-hub/manifest"
)

func TestCartaScopesAndAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/carta/houston.json")
	// Write scopes add to the read scopes, so narrowing a caller to read-only keeps a granted set.
	readScopes := []string{"read_user_info", "read_issuer_info", "read_issuer_capitalizationtablesummary", "read_issuer_stakeholdercapitalizationtable",
		"read_issuer_shareclasses", "read_issuer_stakeholders", "read_issuer_securities", "read_issuer_valuations", "read_issuer_securitiestemplates",
		"read_issuer_interests", "read_issuer_draftsecurities", "read_corporation_info", "read_compensation_benchmarks",
		"read_opencaptables", "read_investor_firms", "read_investor_funds", "read_investor_investments", "read_investor_capitalizationtables",
		"read_investor_stakeholdercapitalizationtable", "read_investor_securities", "read_investor_cashbalances", "read_investor_fundperformance",
		"read_investor_partners", "read_portfolio_info", "read_portfolio_securities", "read_portfolio_issuervaluations", "read_portfolio_transactions",
		"read_portfolio_fundinvestmentdocuments"}
	writeScopes := []string{"readwrite_issuer_securities", "readwrite_issuer_draftsecurities", "readwrite_issuer_secondarytransactions",
		"readwrite_draftissuers", "readwrite_opencaptables", "readwrite_file_upload", "readwrite_investor_capitalcalls",
		"readwrite_investor_carriedinterest", "readwrite_investor_managementfees"}
	// Houston's app signs in to production; a connection's own app to production or the playground.
	for method, login := range map[string]string{"carta": "https://login.app.carta.com", "own_app": "https://login.app.carta.com",
		"playground": "https://login.playground.carta.team"} {
		if m.Auth[method].AuthorizeURL != login+"/o/authorize/" || m.Auth[method].TokenURL != login+"/o/access_token/" {
			t.Fatalf("%s endpoints %s %s", method, m.Auth[method].AuthorizeURL, m.Auth[method].TokenURL)
		}
		for _, access := range []string{"read-only", "read-write"} {
			config := map[string]any{"access": access}
			publisher := map[string]any{"client_id": "houston-client", "client_secret": "houston-secret"}
			if method != "carta" {
				config["own_app"], config["client_id"], config["client_secret"], publisher = true, "fixture-client", "fixture-secret", nil
			}
			r, err := m.Resolve(publisher, config, nil, method)
			if err != nil {
				t.Fatal(err)
			}
			scopes := readScopes
			if access == "read-write" {
				scopes = slices.Concat(readScopes, writeScopes)
			}
			if !slices.Equal(r.Scopes, scopes) {
				t.Fatalf("%s access=%s scopes %v", method, access, r.Scopes)
			}
			token := "carta-" + method
			r.Context.Auth[method]["access_token"] = token
			for _, api := range []string{"https://api.carta.com/v1alpha1", "https://api.playground.carta.team/v1alpha1"} {
				assertRoutes(t, r, token, true,
					"GET "+api+"/user", "GET "+api+"/issuers?pageSize=50", "GET "+api+"/issuers/7/stakeholders/611/equitySummary",
					"GET "+api+"/investors/firms/F/funds/-/metrics", "GET "+api+"/portfolios/P/fundInvestmentDocuments/D:download",
					"POST "+api+"/issuers/7/securities:stockSplitChanges")
				// Capital calls, management fees and secondary transactions read only with readwrite_ scopes;
				// draft issuers return a one-time registration link.
				assertRoutes(t, r, token, access == "read-write",
					"GET "+api+"/investors/firms/F/funds/U/capitalCalls/C", "GET "+api+"/investors/firms/F/funds/U/managementFees/M",
					"GET "+api+"/issuers/7/secondaryTransactions/S", "GET "+api+"/draftIssuers/D", "POST "+api+"/investors/firms/F/funds/U/capitalCalls",
					"POST "+api+"/investors/firms/F/funds/U/capitalCalls/C:adjust", "POST "+api+"/issuers/7/optionExercises/E:updateTaxWithholding",
					"POST "+api+"/issuers/7/secondaryTransactions/S:finalize", "POST "+api+"/draftIssuers", "POST "+api+"/files:upload")
				assertRoutes(t, r, token, false,
					"POST "+api+"/issuers", "DELETE "+api+"/issuers/7", "PATCH "+api+"/issuers/7/stakeholders/611", "GET "+api+"/issuers/7/unlisted",
					"POST "+api+"/issuers/7/securities:otherVerb", "GET "+api+"/issuers/%2e%2e/user", "GET https://api.carta.com/v1/issuers")
			}
			// The token endpoints and lookalike hosts never receive the access token.
			assertRoutes(t, r, token, false,
				"POST https://login.app.carta.com/o/access_token/", "POST https://login.playground.carta.team/o/revoke_token/",
				"GET https://login.app.carta.com/o/userinfo/", "GET https://app.carta.com/v1alpha1/user", "GET https://mock-api.carta.com/v1alpha1/user",
				"GET https://api.carta.com.example.com/v1alpha1/user", "GET https://crm-public-api.app.carta.com/v1/me")
		}
	}
}

// Every credentialed route drops method-override headers, so the upstream method is the one
// the proxy matched.
func assertStripsMethodOverrides(t *testing.T, r *manifest.Resolved, routes ...string) {
	t.Helper()
	for _, route := range routes {
		method, url, _ := strings.Cut(route, " ")
		recipe, err := r.Proxy.HTTPRecipe(method, url, nil)
		if err != nil {
			t.Fatal(err)
		}
		headers, err := recipe.Prepare(r.Context, http.Header{
			"X-Http-Method-Override": {"DELETE"}, "X-Http-Method": {"DELETE"}, "X-Method-Override": {"DELETE"},
		})
		if err != nil {
			t.Fatal(err)
		}
		for _, name := range []string{"X-HTTP-Method-Override", "X-HTTP-Method", "X-Method-Override"} {
			if headers.Get(name) != "" {
				t.Fatalf("%s kept %s", route, name)
			}
		}
	}
}

func TestCartaRoutesStripMethodOverrides(t *testing.T) {
	carta, err := parseManifest(t, "../../connectors/carta/houston.json").Resolve(
		map[string]any{"client_id": "houston-client", "client_secret": "houston-secret"}, map[string]any{"access": "read-only"}, nil, "carta")
	if err != nil {
		t.Fatal(err)
	}
	carta.Context.Auth["carta"]["access_token"] = "carta-token"
	assertStripsMethodOverrides(t, carta, "GET https://api.carta.com/v1alpha1/issuers/7", "POST https://api.carta.com/v1alpha1/issuers/7/securities:stockSplitChanges")
	cartaWrites, err := parseManifest(t, "../../connectors/carta/houston.json").Resolve(
		map[string]any{"client_id": "houston-client", "client_secret": "houston-secret"}, map[string]any{"access": "read-write"}, nil, "carta")
	if err != nil {
		t.Fatal(err)
	}
	cartaWrites.Context.Auth["carta"]["access_token"] = "carta-token"
	assertStripsMethodOverrides(t, cartaWrites, "POST https://api.carta.com/v1alpha1/draftIssuers", "GET https://api.carta.com/v1alpha1/draftIssuers/D1")
	crm, err := parseManifest(t, "../../connectors/carta-crm/houston.json").Resolve(nil, map[string]any{"access": "read-write"}, map[string]any{"token": "crm-key"}, "token")
	if err != nil {
		t.Fatal(err)
	}
	const api = "https://crm-public-api.app.carta.com/v1"
	assertStripsMethodOverrides(t, crm, "GET "+api+"/deals/65a1b2c3d4e5f60718293a4b", "POST "+api+"/companies/search", "POST "+api+"/contacts", "PATCH "+api+"/deals/65a1b2c3d4e5f60718293a4b")
}

// Carta CRM's {id} routes would also match omitted sibling routes such as PATCH
// /v1/deals/batch; a credential-free rule ahead of them sends those without the key.
func TestCartaCRMSiblingRoutesGetNoKey(t *testing.T) {
	r, err := parseManifest(t, "../../connectors/carta-crm/houston.json").Resolve(nil, map[string]any{"access": "read-write"}, map[string]any{"token": "crm-key"}, "token")
	if err != nil {
		t.Fatal(err)
	}
	const api = "https://crm-public-api.app.carta.com/v1"
	for _, route := range []string{"PATCH " + api + "/deals/batch", "PATCH " + api + "/contacts/classifier-prompt", "GET " + api + "/contacts/classifier-prompt",
		"GET " + api + "/deals/custom-fields", "GET " + api + "/email-campaigns/stats", "GET " + api + "/investors/custom-fields"} {
		method, url, _ := strings.Cut(route, " ")
		recipe, err := r.Proxy.HTTPRecipe(method, url, nil)
		if err != nil {
			t.Fatal(err)
		}
		headers, err := recipe.Prepare(r.Context, http.Header{})
		if err != nil || headers.Get("Authorization") != "" {
			t.Fatalf("%s received the key: %v", route, err)
		}
	}
	for _, route := range []string{"PATCH " + api + "/deals/65a1b2c3d4e5f60718293a4b", "GET " + api + "/deals/pipeline-review"} {
		method, url, _ := strings.Cut(route, " ")
		recipe, err := r.Proxy.HTTPRecipe(method, url, nil)
		if err != nil {
			t.Fatal(err)
		}
		if headers, err := recipe.Prepare(r.Context, http.Header{}); err != nil || headers.Get("Authorization") != "crm-key" {
			t.Fatalf("%s lost the key: %v", route, err)
		}
	}
}
