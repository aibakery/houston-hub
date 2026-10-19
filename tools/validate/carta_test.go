package main

import (
	"slices"
	"testing"
)

func TestCartaScopesAndAccessRoutes(t *testing.T) {
	m := parseManifest(t, "../../connectors/carta/houston.json")
	// Write scopes add to the read scopes, so narrowing a caller to read-only keeps a granted set.
	readScopes := []string{"read_user_info", "read_issuer_info", "read_issuer_capitalizationtablesummary", "read_issuer_stakeholdercapitalizationtable",
		"read_issuer_shareclasses", "read_issuer_stakeholders", "read_issuer_securities", "read_issuer_valuations", "read_issuer_securitiestemplates",
		"read_issuer_interests", "read_issuer_draftsecurities", "read_corporation_info", "read_compensation_benchmarks", "read_draftissuers",
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
				// Capital calls, management fees and secondary transactions read only with readwrite_ scopes.
				assertRoutes(t, r, token, access == "read-write",
					"GET "+api+"/investors/firms/F/funds/U/capitalCalls/C", "GET "+api+"/investors/firms/F/funds/U/managementFees/M",
					"GET "+api+"/issuers/7/secondaryTransactions/S", "POST "+api+"/investors/firms/F/funds/U/capitalCalls",
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
