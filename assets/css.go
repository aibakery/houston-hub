package assets

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
	"strings"

	"github.com/tdewolff/parse/v2"
	"github.com/tdewolff/parse/v2/css"
)

var fragment = regexp.MustCompile(`^#[a-zA-Z0-9_.:-]+$`)

// Tokenize rather than search raw CSS: comments, strings and quoted URLs have
// different meanings. Keep styles self-contained even outside our HTTP sandbox.
func validateCSS(source string) error {
	lexer := css.NewLexer(parse.NewInputString(source))
	for {
		kind, raw := lexer.Next()
		if kind == css.ErrorToken {
			if lexer.Err() != io.EOF {
				return fmt.Errorf("invalid SVG CSS")
			}
			return nil
		}
		if kind == css.CommentToken {
			continue
		}
		// Escaped identifiers/URLs can disguise imports or resource functions. Reject
		// these conservatively until there is a use case for decoding them here.
		if bytes.ContainsAny(raw, "\\\x00") {
			return fmt.Errorf("SVG CSS escapes and nulls are unsupported")
		}
		text := strings.ToLower(string(raw))
		switch kind {
		case css.BadURLToken, css.BadStringToken:
			return fmt.Errorf("invalid SVG CSS")
		case css.AtKeywordToken:
			switch text {
			case "@media", "@supports", "@layer", "@container", "@keyframes", "@-webkit-keyframes", "@charset":
			default:
				return fmt.Errorf("SVG CSS rule %s is unsupported", text)
			}
		case css.URLToken:
			if !strings.HasSuffix(text, ")") {
				return fmt.Errorf("invalid SVG CSS URL")
			}
			target := strings.TrimSpace(string(raw[4 : len(raw)-1]))
			if len(target) >= 2 && (target[0] == '\'' || target[0] == '"') && target[len(target)-1] == target[0] {
				target = target[1 : len(target)-1]
			}
			if !fragment.MatchString(target) {
				return fmt.Errorf("external SVG resource is forbidden")
			}
		case css.FunctionToken:
			switch text {
			case "url(", "src(", "image(", "image-set(", "-webkit-image-set(", "expression(":
				return fmt.Errorf("SVG CSS resource or executable function is forbidden")
			}
		case css.IdentToken:
			if text == "behavior" || text == "-moz-binding" {
				return fmt.Errorf("active SVG CSS is forbidden")
			}
		}
	}
}
