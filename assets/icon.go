// Package assets validates self-contained connector images for publication and serving.
package assets

import (
	"bytes"
	"encoding/xml"
	"fmt"
	"image/png"
	"io"
	"strings"
)

// ContentSecurityPolicy permits embedded CSS while isolating directly opened SVGs.
const ContentSecurityPolicy = "default-src 'none'; style-src 'unsafe-inline'; sandbox"

// ValidateIcon checks the supported icon formats and their publication limits.
func ValidateIcon(name string, raw []byte) error {
	switch name {
	case "icon.png":
		cfg, err := png.DecodeConfig(bytes.NewReader(raw))
		if err != nil || cfg.Width != 1024 || cfg.Height != 1024 {
			return fmt.Errorf("icon must be a 1024x1024 PNG")
		}
		return nil
	case "icon.svg":
		return ValidateSVG(raw)
	default:
		return fmt.Errorf("icon must be icon.png or icon.svg")
	}
}

// ValidateSVG permits self-contained graphics and styles, excluding executable
// elements, event handlers, external resources and XML entity declarations.
func ValidateSVG(raw []byte) error {
	if len(raw) == 0 || len(raw) > 512<<10 {
		return fmt.Errorf("icon.svg must be a small SVG document")
	}
	decoder := xml.NewDecoder(bytes.NewReader(raw))
	root, depth := false, 0
	styleDepth := 0
	var style strings.Builder
	allowed := map[string]bool{"svg": true, "style": true, "g": true, "path": true, "rect": true, "circle": true, "ellipse": true, "line": true, "polyline": true, "polygon": true, "defs": true, "linearGradient": true, "radialGradient": true, "stop": true, "clipPath": true, "mask": true, "title": true, "desc": true, "use": true, "filter": true, "feGaussianBlur": true, "feBlend": true, "feFlood": true}
	for {
		token, err := decoder.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("invalid SVG document")
		}
		switch token := token.(type) {
		case xml.StartElement:
			if styleDepth != 0 {
				return fmt.Errorf("SVG style must contain only CSS text")
			}
			if !allowed[token.Name.Local] || (token.Name.Space != "" && token.Name.Space != "http://www.w3.org/2000/svg") {
				return fmt.Errorf("unsupported SVG element %q", token.Name.Local)
			}
			if depth == 0 {
				if root || token.Name.Local != "svg" {
					return fmt.Errorf("invalid SVG root")
				}
				root = true
			}
			depth++
			if token.Name.Local == "style" {
				styleDepth = depth
				style.Reset()
			}
			for _, attr := range token.Attr {
				name, value := strings.ToLower(attr.Name.Local), strings.ToLower(strings.TrimSpace(attr.Value))
				if strings.HasPrefix(name, "on") || name == "base" || strings.Contains(value, "javascript:") || strings.Contains(value, "data:") {
					return fmt.Errorf("active SVG content is forbidden")
				}
				if name == "style" {
					if err := validateCSS(attr.Value); err != nil {
						return err
					}
					continue
				}
				if name == "href" && !strings.HasPrefix(value, "#") {
					return fmt.Errorf("external SVG resource is forbidden")
				}
				if strings.Contains(value, "url(") || strings.Contains(value, `\`) {
					if err := validateCSS(attr.Value); err != nil {
						return err
					}
				}
			}
		case xml.CharData:
			if styleDepth != 0 {
				style.Write(token)
			}
		case xml.EndElement:
			if depth == styleDepth {
				if err := validateCSS(style.String()); err != nil {
					return err
				}
				styleDepth = 0
			}
			depth--
		case xml.Directive:
			return fmt.Errorf("SVG directives are forbidden")
		case xml.ProcInst:
			if token.Target != "xml" {
				return fmt.Errorf("SVG processing instructions are forbidden")
			}
		}
	}
	if !root || depth != 0 {
		return fmt.Errorf("invalid SVG document")
	}
	return nil
}
