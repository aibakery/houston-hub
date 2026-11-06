// Command wordpress-help snapshots native route argument schemas for the actual
// WordPress/WooCommerce operations declared in a connector's resource tables.
package main

import (
	"crypto/sha256"
	"encoding/json"
	"flag"
	"fmt"
	"maps"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
)

type object = map[string]any

func obj(value any) object { result, _ := value.(map[string]any); return result }
func list(value any) []any { result, _ := value.([]any); return result }
func fatal(err error)      { fmt.Fprintln(os.Stderr, err); os.Exit(1) }

type endpoint struct{ name, method, path, topic string }

var placeholders = regexp.MustCompile(`\{(\w+)\}`)
var routeParameters = regexp.MustCompile(`\(\?P<(\w+)>[^)]+\)`)
var quoted = regexp.MustCompile(`"([^"]*)"`)

func declarations(source string) ([]endpoint, error) {
	start := strings.Index(source, "local OPERATIONS = {")
	if start < 0 {
		return nil, fmt.Errorf("missing operation declarations")
	}
	end := strings.Index(source[start:], "\n}")
	if end < 0 {
		return nil, fmt.Errorf("missing operation declarations")
	}
	verbs := map[string]struct {
		method, suffix string
		many           bool
	}{}
	for _, match := range regexp.MustCompile(`(\w+) = \{many = (true|false), method = "(\w+)", suffix = "([^"]*)"`).FindAllStringSubmatch(source[start:start+end], -1) {
		verbs[match[1]] = struct {
			method, suffix string
			many           bool
		}{match[3], match[4], match[2] == "true"}
	}
	groups := map[string][]string{}
	for _, match := range regexp.MustCompile(`(?m)^local (ALL|READ) = (\{[^}]+\})`).FindAllStringSubmatch(source, -1) {
		for _, name := range quoted.FindAllStringSubmatch(match[2], -1) {
			groups[match[1]] = append(groups[match[1]], name[1])
		}
	}
	result := []endpoint{}
	for _, match := range regexp.MustCompile(`\{one = "([^"]+)", many = "([^"]+)", path = "([^"]+)", ops = (ALL|READ|\{[^}]+\}), doc = "([^"]+)"`).FindAllStringSubmatch(source, -1) {
		ops := groups[match[4]]
		if strings.HasPrefix(match[4], "{") {
			for _, name := range quoted.FindAllStringSubmatch(match[4], -1) {
				ops = append(ops, name[1])
			}
		}
		for _, verb := range ops {
			operation, ok := verbs[verb]
			if !ok {
				return nil, fmt.Errorf("unknown operation %s", verb)
			}
			name := match[1]
			if operation.many {
				name = match[2]
			}
			result = append(result, endpoint{verb + name, operation.method, match[3] + operation.suffix, match[5]})
		}
	}
	for _, match := range regexp.MustCompile(`(?m)^\s*(\w+) = \{method = "(\w+)", path = "([^"]+)", doc = "([^"]+)"`).FindAllStringSubmatch(source, -1) {
		result = append(result, endpoint{match[1], match[2], match[3], match[4]})
	}
	slices.SortFunc(result, func(a, b endpoint) int { return strings.Compare(a.name, b.name) })
	return result, nil
}

func main() {
	api := flag.String("api", "", "wordpress or woocommerce")
	snapshot := flag.String("namespace", "", "local snapshot of the public REST namespace index")
	sourceURL := flag.String("source", "", "public namespace URL that supplied the snapshot")
	root := flag.String("root", ".", "Hub repository root")
	flag.Parse()
	if (*api != "wordpress" && *api != "woocommerce") || *snapshot == "" || *sourceURL == "" {
		fatal(fmt.Errorf("-api, -namespace and -source are required"))
	}
	raw, err := os.ReadFile(*snapshot)
	if err != nil {
		fatal(err)
	}
	var index object
	if err = json.Unmarshal(raw, &index); err != nil {
		fatal(err)
	}
	code, err := os.ReadFile(filepath.Join(*root, "connectors", *api, "connector.luau"))
	if err != nil {
		fatal(err)
	}
	endpoints, err := declarations(string(code))
	if err != nil {
		fatal(err)
	}
	type native struct {
		args   object
		params []string
	}
	routes := map[string]native{}
	for path, value := range obj(index["routes"]) {
		params := []string{}
		for _, match := range routeParameters.FindAllStringSubmatch(path, -1) {
			params = append(params, match[1])
		}
		path = strings.TrimPrefix(routeParameters.ReplaceAllString(path, "{}"), "/"+fmt.Sprint(index["namespace"]))
		for _, value := range list(obj(value)["endpoints"]) {
			entry := obj(value)
			for _, method := range list(entry["methods"]) {
				routes[fmt.Sprint(method)+" "+path] = native{obj(entry["args"]), params}
			}
		}
	}
	records := object{}
	missing := []string{}
	for _, endpoint := range endpoints {
		route, ok := routes[endpoint.method+" "+placeholders.ReplaceAllString(endpoint.path, "{}")]
		if !ok {
			missing = append(missing, endpoint.name+": "+endpoint.method+" "+endpoint.path)
			continue
		}
		properties, required := object{}, []string{}
		for name, value := range route.args {
			properties[name] = schema(value)
			// Core rendered-text fields accept their raw string when writing;
			// the namespace still advertises the response's {raw,rendered} shape.
			if *api == "wordpress" && endpoint.method != "GET" && obj(obj(value)["properties"])["raw"] != nil {
				obj(properties[name])["type"] = []string{"string", "object"}
			}
			if obj(value)["required"] == true {
				required = append(required, name)
			}
		}
		for i, field := range placeholders.FindAllStringSubmatch(endpoint.path, -1) {
			if i >= len(route.params) {
				fatal(fmt.Errorf("%s: mismatched path parameters", endpoint.name))
			}
			nativeName := route.params[i]
			if nativeName != field[1] {
				properties[field[1]] = properties[nativeName]
				delete(properties, nativeName)
				required = slices.DeleteFunc(required, func(name string) bool { return name == nativeName })
			}
			if properties[field[1]] == nil {
				properties[field[1]] = object{"type": []string{"integer", "string"}, "minimum": 0, "pattern": "^[A-Za-z0-9_-]+$"}
			}
			if !slices.Contains(required, field[1]) {
				required = append(required, field[1])
			}
		}
		slices.Sort(required)
		input := object{"type": "object", "properties": properties}
		if len(required) > 0 {
			input["required"] = required
		}
		records[endpoint.name] = input
	}
	if len(missing) > 0 {
		fatal(fmt.Errorf("namespace is missing connector routes:\n%s", strings.Join(missing, "\n")))
	}
	if *api == "woocommerce" {
		// The namespace omits these write-only line fields. Keep their nested
		// contract from the provider's order-refunds reference, not its response.
		refundID := object{"type": []string{"integer", "string"}, "minimum": 1, "pattern": "^[0-9]+$"}
		obj(obj(records["createOrderRefund"])["properties"])["line_items"] = object{"type": "array", "items": object{
			"type": "object", "required": []string{"id"}, "properties": object{
				"id": refundID, "quantity": object{"type": "integer", "minimum": 1},
				"refund_total": object{"type": "number"}, "refund_tax": object{"type": "array", "items": object{
					"type": "object", "required": []string{"id", "refund_total"}, "properties": object{
						"id": refundID, "refund_total": object{"type": "number"}}}}}},
			"description": "Original order lines to refund. Without compute_totals, supply refund_total and applicable refund_tax. With compute_totals (WooCommerce 11.1+), quantity can determine the amount; confirm support with previewOrderRefund first, since older stores silently ignore the flag."}
		previewItem := obj(obj(obj(obj(records["previewOrderRefund"])["properties"])["line_items"])["items"])
		previewItem["anyOf"] = []any{object{"required": []string{"quantity"}}, object{"required": []string{"refund_total"},
			"properties": object{"refund_total": object{"type": "number", "not": object{"const": 0}}}}}
		if err = batches(endpoints, records); err != nil {
			fatal(err)
		}
		// The namespace index exposes the tool's response fields, but omits
		// its write-only confirmation (documented in system-status-tools).
		records["runSystemStatusTool"] = object{"type": "object", "properties": object{
			"id": object{"type": "string", "minLength": 1}, "confirm": object{"type": "boolean", "default": false,
				"description": "Set true to execute the selected system tool; inspect it with getSystemStatusTool first."}}, "required": []string{"id"}}
	}
	exampleBytes, err := os.ReadFile(filepath.Join(*root, "tools", "wordpress-help", *api+"-examples.json"))
	if err != nil {
		fatal(err)
	}
	examples := map[string][]object{}
	if err = json.Unmarshal(exampleBytes, &examples); err != nil {
		fatal(err)
	}
	cases := object{}
	for _, endpoint := range endpoints {
		if len(examples[endpoint.name]) == 0 {
			fatal(fmt.Errorf("%s: missing authored example", endpoint.name))
		}
		requests := []object{}
		for _, example := range examples[endpoint.name] {
			request, err := exampleRequest(endpoint, example)
			if err != nil {
				fatal(err)
			}
			requests = append(requests, request)
		}
		cases[endpoint.name] = requests
	}
	for name := range examples {
		if records[name] == nil {
			fatal(fmt.Errorf("orphaned example %s", name))
		}
	}
	directory := filepath.Join(*root, "connectors", *api, "lib")
	if err = os.MkdirAll(directory, 0755); err != nil {
		fatal(err)
	}
	for name, value := range map[string]any{"route-schemas": records, "examples": examples, "example-requests": cases} {
		data, err := json.MarshalIndent(value, "", "\t")
		if err != nil {
			fatal(err)
		}
		output := fmt.Sprintf("-- Code generated by go run ./tools/wordpress-help -api %s -namespace <snapshot> -source <URL>; DO NOT EDIT.\n-- Source: %s\n-- SHA-256: %x\n-- Authored examples: tools/wordpress-help/%s-examples.json\nreturn json.decode([====[\n%s\n]====])\n", *api, *sourceURL, sha256.Sum256(raw), *api, data)
		if err = os.WriteFile(filepath.Join(directory, name+".luau"), []byte(output), 0644); err != nil {
			fatal(err)
		}
	}
}

func exampleRequest(endpoint endpoint, example object) (object, error) {
	args := maps.Clone(example)
	path := endpoint.path
	for _, match := range placeholders.FindAllStringSubmatch(path, -1) {
		value, ok := args[match[1]]
		if !ok {
			return nil, fmt.Errorf("%s example is missing path parameter %s", endpoint.name, match[1])
		}
		path = strings.ReplaceAll(path, match[0], fmt.Sprint(value))
		delete(args, match[1])
	}
	request := object{"method": endpoint.method}
	upload := endpoint.name == "uploadMedia"
	if upload {
		request["file"] = args["path"]
		request["content_type"] = strings.ToLower(fmt.Sprint(args["content_type"]))
		request["filename"] = args["filename"]
		if request["filename"] == nil {
			request["filename"] = filepath.Base(fmt.Sprint(args["path"]))
		}
		delete(args, "path")
		delete(args, "filename")
		delete(args, "content_type")
	}
	if endpoint.method == "GET" || endpoint.method == "DELETE" || upload {
		keys := slices.Sorted(maps.Keys(args))
		parts := []string{}
		for _, key := range keys {
			values, array := args[key].([]any)
			if !array {
				values = []any{args[key]}
			}
			for _, value := range values {
				name := key
				if array {
					name += "%5B%5D"
				}
				parts = append(parts, name+"="+strings.ReplaceAll(url.QueryEscape(fmt.Sprint(value)), "+", "%20"))
			}
		}
		if len(parts) > 0 {
			path += "?" + strings.Join(parts, "&")
		}
	} else {
		request["body"] = args
	}
	request["path"] = path
	return request, nil
}

// WooCommerce's namespace index reports the resource fields for batch routes,
// while the wire body wraps them in create/update/delete arrays. Derive those
// item schemas from the same resource's real individual routes.
func batches(endpoints []endpoint, records object) error {
	byRoute := map[string]string{}
	for _, endpoint := range endpoints {
		byRoute[endpoint.method+" "+endpoint.path] = endpoint.name
	}
	for _, endpoint := range endpoints {
		base, batch := strings.CutSuffix(endpoint.path, "/batch")
		if !batch {
			continue
		}
		parents := []string{}
		for _, field := range placeholders.FindAllStringSubmatch(endpoint.path, -1) {
			parents = append(parents, field[1])
		}
		properties := object{}
		for _, parent := range parents {
			properties[parent] = obj(obj(records[endpoint.name])["properties"])[parent]
		}
		for _, action := range []struct{ name, route string }{{"create", "POST " + base}, {"update", "PUT " + base + "/{id}"}, {"delete", "DELETE " + base + "/{id}"}} {
			operation := byRoute[action.route]
			if operation == "" {
				continue
			}
			source := obj(records[operation])
			var item any
			if action.name == "delete" {
				item = obj(source["properties"])["id"]
			} else {
				fields, required := object{}, []string{}
				for name, property := range obj(source["properties"]) {
					if !slices.Contains(parents, name) {
						fields[name] = property
					}
				}
				for _, field := range stringsList(source["required"]) {
					if !slices.Contains(parents, field) {
						required = append(required, field)
					}
				}
				body := object{"type": "object", "properties": fields}
				if len(required) > 0 {
					body["required"] = required
				}
				item = body
			}
			if item == nil {
				return fmt.Errorf("%s: missing %s item schema", endpoint.name, action.name)
			}
			properties[action.name] = object{"type": "array", "items": item, "description": "Items to " + action.name + ". The server's batch limit is normally 100 total items across all actions."}
		}
		if len(properties) == len(parents) {
			return fmt.Errorf("%s: no batch resource operations", endpoint.name)
		}
		input := object{"type": "object", "properties": properties, "additionalProperties": false}
		if len(parents) > 0 {
			input["required"] = parents
		}
		records[endpoint.name] = input
	}
	return nil
}

func stringsList(value any) []string {
	values, _ := value.([]string)
	return values
}

// WordPress route arguments use JSON Schema with required as a per-field boolean.
// Provider-specific callbacks/context describe server behavior, not validation.
func schema(value any) any {
	if array, ok := value.([]any); ok {
		out := make([]any, len(array))
		for i, item := range array {
			out[i] = schema(item)
		}
		return out
	}
	if source := obj(value); source != nil {
		out := object{}
		for key, child := range source {
			switch key {
			case "sanitize_callback", "validate_callback", "context", "arg_options":
			case "required":
				if _, ok := child.(bool); !ok {
					out[key] = child
				}
			case "format":
				if child == "date-time" {
					// WordPress accepts site-local ISO dates without an offset.
					out["anyOf"] = []any{object{"format": "date-time"}, object{"pattern": `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?$`}}
				} else {
					out[key] = child
				}
			case "enum":
				if options := obj(child); options != nil {
					values := []any{}
					seen := map[string]bool{}
					for _, name := range slices.Sorted(maps.Keys(options)) {
						encoded, _ := json.Marshal(options[name])
						if !seen[string(encoded)] {
							seen[string(encoded)] = true
							values = append(values, options[name])
						}
					}
					out[key] = values
				} else {
					out[key] = child
				}
			case "properties":
				properties, required := object{}, []string{}
				for name, property := range obj(child) {
					properties[name] = schema(property)
					if obj(property)["required"] == true {
						required = append(required, name)
					}
				}
				out[key] = properties
				if len(required) > 0 {
					slices.Sort(required)
					out["required"] = required
				}
			default:
				if slices.Contains([]string{"items", "additionalProperties", "oneOf", "anyOf", "allOf", "not", "if", "then", "else"}, key) {
					out[key] = schema(child)
				} else {
					out[key] = child
				}
			}
		}
		return out
	}
	return value
}
