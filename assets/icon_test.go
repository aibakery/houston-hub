package assets

import (
	"os"
	"testing"
)

func TestOfficialMercurySVG(t *testing.T) {
	// Unmodified https://mercury.com/icon.svg, retrieved 2026-10-10. The embedded
	// media query was rejected by the original server validator.
	raw, err := os.ReadFile("testdata/mercury.svg")
	if err != nil {
		t.Fatal(err)
	}
	if err := ValidateIcon("icon.svg", raw); err != nil {
		t.Fatal(err)
	}
}

func TestSelfContainedSVGStyles(t *testing.T) {
	for _, source := range []string{
		`<svg xmlns="http://www.w3.org/2000/svg"><style>@media (prefers-color-scheme:dark){#logo{fill:#f4f5f9}}</style><path id="logo" fill="#272735" d="M0 0L1 1"/></svg>`,
		`<svg><style><![CDATA[/* brand colors */ .a{fill:rgb(1, 2, 3);opacity:.5} @supports (fill:currentColor){.a{fill:currentColor}}]]></style><path class="a"/></svg>`,
		`<svg><defs><linearGradient id="g"><stop stop-color="red"/></linearGradient></defs><path style="fill: url('#g'); stroke: blue; mask-type:alpha"/></svg>`,
		`<svg><style>.logo { --paint: url("#g"); fill:var(--paint); }</style></svg>`,
		`<svg><path fill="url( &quot;#g&quot; ) red"/></svg>`,
		`<svg><style>@keyframes pulse {from{opacity:0}to{opacity:1}} .a{animation:pulse 1s}</style></svg>`,
	} {
		if err := ValidateSVG([]byte(source)); err != nil {
			t.Errorf("rejected %s: %v", source, err)
		}
	}
}

func TestSVGRejectsActiveAndExternalContent(t *testing.T) {
	for _, source := range []string{
		`<svg onerror="alert(1)"/>`, `<svg><script>alert(1)</script></svg>`,
		`<svg><foreignObject/></svg>`, `<svg><image href="https://example.com/x"/></svg>`,
		`<svg><use href="https://example.com/x#icon"/></svg>`,
		`<svg><path fill="url(https://example.com/x)"/></svg>`,
		`<!DOCTYPE svg SYSTEM "https://example.com/x"><svg/>`,
		`<svg><style>@import "https://example.com/style.css";</style></svg>`,
		`<svg><style>@IMPORT url(//example.com/style.css);</style></svg>`,
		`<svg><style>@im<!-- split -->port "https://example.com/x";</style></svg>`,
		`<svg><style>@\69mport "https://example.com/x";</style></svg>`,
		`<svg><style>.a{fill:u\72l(https://example.com/x)}</style></svg>`,
		`<svg><style>.a{fill:URL('https://example.com/x')}</style></svg>`,
		`<svg><style>.a{fill:url(data:image/svg+xml,xxx)}</style></svg>`,
		`<svg><style>.a{fill:url(/account)}</style></svg>`,
		`<svg><style>.a{fill:url(//example.com/x)}</style></svg>`,
		`<svg><style>.a{fill:url('')}</style></svg>`,
		`<svg><style>.a{fill:image-set("https://example.com/x" 1x)}</style></svg>`,
		`<svg><style>.a{fill:src("https://example.com/x")}</style></svg>`,
		`<svg><style>@font-face{font-family:evil;src:url(https://example.com/font)}</style></svg>`,
		`<svg><style>.a{width:expression(alert(1))}</style></svg>`,
		`<svg><path style="behavior:evil"/></svg>`,
		`<svg><path style="-moz-binding:url(#binding)"/></svg>`,
		`<svg><path style="fill:url(&quot;https://example.com/x&quot;)"/></svg>`,
		`<svg><path style="fill:&#117;rl(https://example.com/x)"/></svg>`,
		`<svg><path fill="u\72l(https://example.com/x)"/></svg>`,
		`<svg><style><g/>.a{fill:red}</style></svg>`,
		`<svg><style>.a{fill:url("unterminated)}</style></svg>`,
		`<svg><style>.a{fill:url(#g}</style></svg>`,
	} {
		if err := ValidateSVG([]byte(source)); err == nil {
			t.Errorf("accepted unsafe SVG %s", source)
		}
	}
}
