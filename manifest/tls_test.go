package manifest

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"math/big"
	"strings"
	"testing"
	"time"
)

func testCertificate(t *testing.T) string {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "Example CA"}, NotBefore: time.Now(), NotAfter: time.Now().Add(time.Hour), IsCA: true, BasicConstraintsValid: true}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	return string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}))
}

// tlsManifest is a Postgres connection whose TLS settings come from tls and the
// extra config fields.
func tlsManifest(tls, fields string) []byte {
	return []byte(`{"schema_version":1,"name":"Postgres","files":["connector.luau"],
		"config":{"host":{"type":"string","label":"Host","required":true},"password":{"type":"secret","label":"Password","required":true}` + fields + `},
		"proxy":[{"match":{"protocol":"postgres"},"action":{"connection":{"host":"{{config.host}}","database":"app","user":"reader","password":"{{config.password}}","tls":` + tls + `}}}]}`)
}

const tlsFields = `,"tls_mode":{"type":"string","label":"TLS mode","default":"verify-full","options":[{"value":"verify-full","label":"Full"},{"value":"verify-ca","label":"CA"},{"value":"require","label":"Require"}]},
	"ca":{"type":"string","label":"CA certificate","multiline":true,"format":"pem"}`

func TestDatabaseTLSSettingsResolve(t *testing.T) {
	m, err := Parse(tlsManifest(`{"mode":"{{config.tls_mode}}","ca":"{{config.ca}}"}`, tlsFields))
	if err != nil {
		t.Fatal(err)
	}
	ca := testCertificate(t)
	for _, c := range []struct {
		config     map[string]any
		mode, want string
	}{
		{map[string]any{}, "verify-full", ""}, // Connections saved before these fields existed.
		{map[string]any{"tls_mode": "require"}, "require", ""},
		{map[string]any{"tls_mode": "verify-ca", "ca": ca}, "verify-ca", ca},
		{map[string]any{"ca": ca}, "verify-full", ca},
	} {
		c.config["host"], c.config["password"] = "203.0.113.7", "secret"
		r, err := m.Resolve(nil, c.config, nil, "")
		if err != nil {
			t.Fatal(err)
		}
		target, err := m.Proxy[0].ResolveDatabase(r.Context)
		if err != nil || target.TLSMode != c.mode || target.TLSCA != c.want {
			t.Fatalf("%v: %q %v", c.config, target.TLSMode, err)
		}
	}
	for field, want := range map[string]string{"tls_mode": "config.tls_mode: value outside options", "ca": "config.ca: must be PEM certificates"} {
		config := map[string]any{"host": "db.example.com", "password": "secret", field: "disable"}
		if _, err := m.Resolve(nil, config, nil, ""); err == nil || !strings.Contains(err.Error(), want) {
			t.Fatalf("%s: want %q, got %v", field, want, err)
		}
	}
}

func TestDatabaseTLSSettingsValidate(t *testing.T) {
	ca, _ := json.Marshal(testCertificate(t))
	if _, err := Parse(tlsManifest(`{"mode":"verify-ca","ca":`+string(ca)+`}`, "")); err != nil {
		t.Fatalf("literal CA rejected: %v", err)
	}
	for _, c := range [][2]string{
		{`{"mode":"disable"}`, ""},
		{`{"mode":"verify-full","ca":"-----BEGIN CERTIFICATE-----"}`, ""},
		{`{"mode":"{{config.mode}}"}`, `,"mode":{"type":"string","label":"Mode"}`},
		{`{"mode":"{{config.mode}}"}`, `,"mode":{"type":"string","label":"Mode","options":[{"value":"verify-full","label":"Full"},{"value":"disable","label":"Off"}]}`},
		{`{"mode":"verify-{{config.mode}}"}`, `,"mode":{"type":"string","label":"Mode","options":[{"value":"full","label":"Full"}]}`},
		{`{"mode":"verify-full","ca":"{{config.ca}}"}`, `,"ca":{"type":"string","label":"CA","multiline":true}`},
		{`{"mode":"verify-full","ca":"{{config.ca}}"}`, `,"ca":{"type":"secret","label":"CA"}`},
	} {
		if _, err := Parse(tlsManifest(c[0], c[1])); err == nil {
			t.Fatalf("accepted TLS %s with fields %s", c[0], c[1])
		}
	}
}

func TestParseCertificates(t *testing.T) {
	ca := testCertificate(t)
	if certificates, err := ParseCertificates("subject=Example CA\n" + ca + strings.ReplaceAll(ca, "\n", "\r\n")); err != nil || len(certificates) != 2 {
		t.Fatalf("two certificates: %d %v", len(certificates), err)
	}
	key := "-----BEGIN PRIVATE KEY-----\nMIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg\n-----END PRIVATE KEY-----\n"
	for input, want := range map[string]string{
		"":                     "must be PEM certificates",
		"MIIBizCCATGgAwIBAgIU": "must be PEM certificates",
		ca[:len(ca)-30]:        "must be PEM certificates", // Truncated before its END line.
		ca + "garbage":         "must be PEM certificates",
		ca + key:               "contains a PRIVATE KEY",
		"-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n": "certificate 1 is not a valid X.509 certificate",
	} {
		if _, err := ParseCertificates(input); err == nil || !strings.Contains(err.Error(), want) {
			t.Fatalf("%q: want %q, got %v", input, want, err)
		}
	}
	field := Field{Type: "string", Label: "CA", Multiline: true, Format: "pem"}
	if ValidateValue(field, "") != nil || ValidateValue(field, ca) != nil || ValidateValue(field, "junk") == nil {
		t.Fatal("pem field validation")
	}
}
