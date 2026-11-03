package manifest

import (
	"bytes"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"slices"
)

// TLSModes are the database TLS modes, strictest first. verify-full checks the
// certificate chain and host name, verify-ca only the chain, and require
// encrypts without checking the certificate. No mode connects without TLS.
var TLSModes = []string{"verify-full", "verify-ca", "require"}

// ParseCertificates reads one or more PEM certificates and nothing else, so a
// pasted private key or a truncated certificate is rejected.
func ParseCertificates(text string) ([]*x509.Certificate, error) {
	var certificates []*x509.Certificate
	rest := []byte(text)
	for {
		block, next := pem.Decode(rest)
		if block == nil {
			break
		}
		if block.Type != "CERTIFICATE" {
			return nil, fmt.Errorf("contains a %s; paste only certificates", block.Type)
		}
		certificate, err := x509.ParseCertificate(block.Bytes)
		if err != nil {
			return nil, fmt.Errorf("certificate %d is not a valid X.509 certificate", len(certificates)+1)
		}
		certificates = append(certificates, certificate)
		rest = next
	}
	if len(certificates) == 0 || len(bytes.TrimSpace(rest)) != 0 {
		return nil, fmt.Errorf("must be PEM certificates, each from -----BEGIN CERTIFICATE----- to -----END CERTIFICATE-----")
	}
	return certificates, nil
}

// validateTLS accepts literals, or one whole reference to a nonsecret setting
// the form validates: a choice among TLSModes and a pem-formatted CA.
func (m *Manifest) validateTLS(t TLS, used map[string]bool) error {
	if templated(t.Mode) {
		f, err := m.tlsSetting(t.Mode, used)
		if err != nil {
			return err
		}
		if f.Type != "string" || len(f.Options) == 0 || slices.ContainsFunc(f.Options, func(o Option) bool { return !slices.Contains(TLSModes, o.Value) }) {
			return fmt.Errorf("a TLS mode reference requires a string field whose options are TLS modes")
		}
	} else if !slices.Contains(TLSModes, t.Mode) {
		return fmt.Errorf("TLS mode must be verify-full, verify-ca or require")
	}
	if templated(t.CA) {
		f, err := m.tlsSetting(t.CA, used)
		if err != nil {
			return err
		}
		if f.Format != "pem" {
			return fmt.Errorf("a TLS CA reference requires a pem-formatted field")
		}
	} else if t.CA != "" {
		if _, err := ParseCertificates(t.CA); err != nil {
			return fmt.Errorf("TLS CA %w", err)
		}
	}
	return nil
}

func (m *Manifest) tlsSetting(value string, used map[string]bool) (Field, error) {
	parts, err := parseTemplate(value)
	if err != nil {
		return Field{}, err
	}
	if len(parts) != 1 || len(parts[0].refs) != 1 {
		return Field{}, fmt.Errorf("a TLS setting must be a literal or one whole-value reference")
	}
	if err := m.template(value, "destination", used); err != nil {
		return Field{}, err
	}
	return m.reference(parts[0].refs[0])
}

// resolve renders the connection's TLS settings. An unset CA setting means the
// public certificate authorities.
func (t TLS) resolve(c Context) (mode, ca string, err error) {
	if mode, err = RenderString(t.Mode, c); err != nil {
		return "", "", err
	}
	if !slices.Contains(TLSModes, mode) {
		return "", "", fmt.Errorf("invalid TLS mode")
	}
	if ca, err = RenderString(t.CA, c); err != nil && !errors.Is(err, errUnresolved) {
		return "", "", err
	}
	return mode, ca, nil
}
