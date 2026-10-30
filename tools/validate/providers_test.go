package main

import (
	"encoding/base64"
	"github.com/aibakery/houston-hub/manifest"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Each method exercises the actual shared resolver and native injection recipe.
// Provider execution is separately covered by the bundle's mocked Luau fixtures.
func TestEveryProviderAuthenticationAndTransport(t *testing.T) {
	paths, err := filepath.Glob("../../connectors/*/houston.json")
	if err != nil {
		t.Fatal(err)
	}
	endpoints := map[string][2]string{
		"attio": {"GET", "https://api.attio.com/v2/self"}, "chembl": {"GET", "https://www.ebi.ac.uk/chembl/api/data/molecule.json"}, "clinicaltrials": {"GET", "https://clinicaltrials.gov/api/v2/studies"}, "granola": {"GET", "https://public-api.granola.ai/v1/notes"},
		"gmail": {"GET", "https://gmail.googleapis.com/gmail/v1/users/me/profile"}, "gdrive": {"GET", "https://www.googleapis.com/drive/v3/files"}, "gsheets": {"GET", "https://sheets.googleapis.com/v4/spreadsheets/s1"}, "gforms": {"GET", "https://forms.googleapis.com/v1/forms/f1"}, "gdocs": {"GET", "https://docs.googleapis.com/v1/documents/d1"}, "gslides": {"GET", "https://slides.googleapis.com/v1/presentations/p1"},
		"gcalendar": {"GET", "https://www.googleapis.com/calendar/v3/users/me/calendarList"}, "dropbox": {"POST", "https://api.dropboxapi.com/2/files/list_folder"},
		"slack": {"GET", "https://slack.com/api/auth.test"}, "fastmail": {"GET", "https://api.fastmail.com/jmap/session"},
		"notion":      {"GET", "https://api.notion.com/v1/users/me"},
		"mercury":     {"GET", "https://api.mercury.com/api/v1/accounts"},
		"x":           {"GET", "https://api.x.com/2/tweets/123"},
		"linkedin":    {"GET", "https://api.linkedin.com/v2/userinfo"},
		"woocommerce": {"GET", "https://shop.example.com/wp-json/wc/v3/orders"},
		"prestashop":  {"GET", "https://shop.example.com/api/orders"},
		"dolibarr":    {"GET", "https://erp.example.com/api/index.php/status"},
		"calcom":      {"GET", "https://api.cal.com/v2/me"},
		"calendly":    {"GET", "https://api.calendly.com/users/me"},
		"carta":       {"GET", "https://api.carta.com/v1alpha1/user"},
		"carta-crm":   {"GET", "https://crm-public-api.app.carta.com/v1/me"},
		"resend":      {"GET", "https://api.resend.com/domains"},
		"stripe":      {"GET", "https://api.stripe.com/v1/balance"},
		"wise":        {"GET", "https://api.wise.com/v2/profiles"},
		"github":      {"GET", "https://api.github.com/user"},
		"meta":        {"GET", "https://graph.facebook.com/v26.0/me"},
		"gusto":       {"GET", "https://api.gusto.com/v1/token_info"},
		"assessfirst": {"GET", "https://app.assessfirst.com/betty-V2/locales"},
		"tipeee":      {"GET", "https://api.tipeee.com/v2.0/categories"},
		"linear":      {"GET", "https://api.linear.app/graphql"},
		"vercel":      {"GET", "https://api.vercel.com/v2/user"},
		"figma":       {"GET", "https://api.figma.com/v1/me"},
		"biorxiv":     {"GET", "https://api.biorxiv.org/details/biorxiv/10.1101/339747/na/json"},
		"pubmed":      {"POST", "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"},
		"exa":         {"POST", "https://api.exa.ai/search"},
		"sentry":      {"GET", "https://us.sentry.io/api/0/organizations/"},
		"posthog":     {"GET", "https://us.posthog.com/api/organizations/"},
	}
	for _, path := range paths {
		provider := filepath.Base(filepath.Dir(path))
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		m, err := manifest.Parse(raw)
		if err != nil {
			t.Fatal(err)
		}
		keys := m.MethodKeys()
		if len(keys) == 0 {
			keys = []string{""}
		}
		for _, method := range keys {
			t.Run(provider+"/"+method, func(t *testing.T) {
				publisher := map[string]any{}
				config := map[string]any{}
				if m.Auth[method].Type == "oauth2" {
					client := config
					if m.Auth[method].PublisherClient() {
						client = publisher
					}
					client["client_id"] = "synthetic-public-client"
					client["client_secret"] = "synthetic-client-secret"
				}
				input := map[string]any{}
				if (provider == "carta" || provider == "gusto") && method != provider {
					config["own_app"] = true
				}
				if m.Proxy[0].Match.Protocol != "http" {
					config["host"] = "database.example.com"
					switch provider {
					case "imap": // A mail server has no database.
					case "redis":
						config["database"] = 2
					default:
						config["database"] = "sample"
					}
					config["username"] = "reader"
					config["password"] = "synthetic-root-secret"
				}
				if method != "" && m.Auth[method].Type == "manual" {
					input["token"] = "synthetic-method-secret"
				}
				authorization := "Bearer synthetic-method-secret"
				credentialHeader := "Authorization"
				if provider == "carta-crm" || provider == "linear" { // Carta CRM and Linear take the bare API key.
					authorization = "synthetic-method-secret"
				}
				if provider == "woocommerce" {
					config["store_host"] = "shop.example.com"
					input = map[string]any{"consumer_key": "synthetic-method-key", "consumer_secret": "synthetic-method-secret"}
					authorization = "Basic " + base64.StdEncoding.EncodeToString([]byte("synthetic-method-key:synthetic-method-secret"))
				}
				if provider == "sentry" {
					config["organization"] = "acme"
				}
				if provider == "prestashop" { // A 32-character key is the Basic username, with no password.
					config["store_host"] = "shop.example.com"
					input["token"] = "synthetic-method-secret-32-chars"
					authorization = "Basic " + base64.StdEncoding.EncodeToString([]byte("synthetic-method-secret-32-chars:"))
				}
				if provider == "assessfirst" { // AssessFirst reads the bare token from its own header.
					credentialHeader = "AF-Token"
					authorization = "synthetic-method-secret"
				}
				if provider == "figma" && method == "token" { // Figma reads personal tokens from its own header.
					credentialHeader = "X-Figma-Token"
					authorization = "synthetic-method-secret"
				}
				if provider == "exa" { // Exa reads the bare API key from its own header.
					credentialHeader = "x-api-key"
					authorization = "synthetic-method-secret"
				}
				if method == "" && m.Proxy[0].Match.Protocol == "http" { // A public API takes no credential, so its rules drop the caller's.
					authorization = ""
				}
				if provider == "clinicaltrials" { // ClinicalTrials.gov's rule leaves the caller's headers unchanged.
					authorization = "caller-forgery"
				}
				if provider == "dolibarr" { // Dolibarr reads the bare key from its own header.
					config["host"] = "erp.example.com"
					credentialHeader = "DOLAPIKEY"
					authorization = "synthetic-method-secret"
				}
				r, err := m.Resolve(publisher, config, input, method)
				if err != nil {
					t.Fatal(err)
				}
				for k, v := range r.PublicConfig {
					if m.Config[k].Type == "secret" || strings.Contains(strings.TrimSpace(stringValue(v)), "secret") {
						t.Fatalf("private value in runtime config: %s", k)
					}
				}
				if m.Proxy[r.ProxyIndices[0]].Match.Protocol == "http" {
					if m.Auth[method].Type == "oauth2" {
						authorization = "Bearer synthetic-oauth-token"
						r.Context.Auth[method]["access_token"] = "synthetic-oauth-token"
						if len(m.Auth[method].Scopes) > 0 && len(r.Scopes) == 0 {
							t.Fatal("OAuth scopes missing")
						}
					}
					if err := m.RequireCredentials(r.Context); err != nil {
						t.Fatal(err)
					}
					ep := endpoints[provider]
					if provider == "notion" && method == "admin" {
						ep = [2]string{"GET", "https://api.notion.com/admin/v1/legal_holds"}
					}
					recipe, err := r.Proxy.HTTPRecipe(ep[0], ep[1], nil)
					if err != nil {
						t.Fatal(err)
					}
					h, err := recipe.Prepare(r.Context, http.Header{"Authorization": []string{"caller-forgery"}})
					if err != nil {
						t.Fatal(err)
					}
					if provider == "tipeee" {
						prepared, err := recipe.PrepareURL(r.Context)
						if err != nil || prepared != ep[1]+"?access_token=synthetic-method-secret" || h.Get("Authorization") != "" {
							t.Fatalf("wrong query credential injection: %v", err)
						}
					} else if h.Get(credentialHeader) != authorization {
						t.Fatalf("wrong injection %q", h.Get(credentialHeader))
					}
					if _, err := r.Proxy.HTTPRecipe("GET", "https://unlisted.example.com/", nil); err == nil {
						t.Fatal("unlisted origin accepted")
					}
				} else {
					db, err := m.Proxy[r.ProxyIndices[0]].ResolveDatabase(r.Context)
					if err != nil {
						t.Fatal(err)
					}
					if db.Password != "synthetic-root-secret" || db.Host != "database.example.com" || db.TLSMode != "verify-full" {
						t.Fatalf("invalid native database recipe: %#v", db)
					}
				}
			})
		}
	}
}
func stringValue(v any) string { s, _ := v.(string); return s }

func TestFastmailDiscoveredOrigins(t *testing.T) {
	raw, err := os.ReadFile("../../connectors/fastmail/houston.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := manifest.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	r, err := m.Resolve(nil, nil, map[string]any{"token": "fixture-token"}, "token")
	if err != nil {
		t.Fatal(err)
	}
	p := r.Proxy
	for _, host := range []string{"api.fastmail.com", "phl.api.fastmail.com", "ams.api.fastmail.com", "jmap.fastmail.com"} {
		for _, route := range [][2]string{{"GET", "/jmap/session"}, {"POST", "/jmap/api/"}, {"POST", "/jmap/upload/u1/"}, {"GET", "/jmap/download/u1/blob/file"}} {
			recipe, err := p.HTTPRecipe(route[0], "https://"+host+route[1], nil)
			if err != nil {
				t.Fatal(err)
			}
			h, err := recipe.Prepare(r.Context, nil)
			if err != nil || h.Get("Authorization") != "Bearer fixture-token" {
				t.Fatalf("%s: %v %v", host, h, err)
			}
		}
	}
	for _, host := range []string{"fastmailusercontent.com", "www.fastmailusercontent.com", "phl-www.fastmailusercontent.com"} {
		recipe, err := p.HTTPRecipe("GET", "https://"+host+"/jmap/download/u1/blob/file?type=text%2Fplain", nil)
		if err != nil {
			t.Fatal(err)
		}
		h, err := recipe.Prepare(r.Context, nil)
		if err != nil || h.Get("Authorization") != "Bearer fixture-token" {
			t.Fatalf("%s: %v %v", host, h, err)
		}
		for _, route := range [][2]string{{"POST", "/jmap/api/"}, {"POST", "/jmap/upload/u1/"}, {"GET", "/other"}} {
			if _, err := p.HTTPRecipe(route[0], "https://"+host+route[1], nil); err == nil {
				t.Fatalf("download host accepted %v", route)
			}
		}
	}
	for _, host := range []string{"fastmail.com", "app.fastmail.com", "evilapi.fastmail.com", "api.fastmail.com.evil.test", "www.fastmailusercontent.com.evil.test"} {
		if _, err := p.HTTPRecipe("GET", "https://"+host+"/jmap/download/u1/blob/file", nil); err == nil {
			t.Fatalf("accepted %s", host)
		}
	}
}

func TestXPublicReadOnlyProxy(t *testing.T) {
	raw, err := os.ReadFile("../../connectors/x/houston.json")
	if err != nil {
		t.Fatal(err)
	}
	m, err := manifest.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	r, err := m.Resolve(nil, nil, map[string]any{"token": "fixture-x-token"}, "token")
	if err != nil {
		t.Fatal(err)
	}
	if !m.Stateless {
		t.Fatal("public X browsing should offer the billing preview")
	}
	p := r.Proxy
	for _, path := range []string{"/2/tweets?ids=1,2", "/2/tweets/123", "/2/tweets/search/recent?query=test", "/2/tweets/search/all?query=test", "/2/users/123", "/2/users/by/username/XDevelopers", "/2/users/123/tweets", "/2/users/123/mentions"} {
		recipe, err := p.HTTPRecipe("GET", "https://api.x.com"+path, nil)
		if err != nil {
			t.Fatal(err)
		}
		headers, err := recipe.Prepare(r.Context, http.Header{"Authorization": {"forged"}})
		if err != nil || headers.Get("Authorization") != "Bearer fixture-x-token" {
			t.Fatalf("credential injection: %v", err)
		}
		if _, err := p.HTTPRecipe("POST", "https://api.x.com"+path, nil); err == nil {
			t.Fatalf("write accepted: %s", path)
		}
	}
	for _, url := range []string{"https://api.x.com/2/users/123/bookmarks", "https://api.x.com/2/users/123/timelines/reverse_chronological", "https://api.x.com/2/dm_events", "https://api.x.com.evil.test/2/tweets/123", "https://api.twitter.com/2/tweets/123"} {
		if _, err := p.HTTPRecipe("GET", url, nil); err == nil {
			t.Fatalf("unexpected endpoint accepted: %s", url)
		}
	}
}
