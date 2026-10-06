// Package analysis typechecks bundled Luau against trusted native primitives and
// the same interface definitions used by runtime guards. Analysis is a publication
// check, never a grant of transport authority or a proof of provider behavior.
package analysis

import (
	"context"
	"fmt"
	"github.com/aibakery/houston-hub/interfaces"
	"github.com/aibakery/houston-hub/manifest"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

const hosts = `--!strict
local http: {request: ({url:string,method:string?,headers:{[string]:string}?,body:string?,src:string?,dest:string?}) -> {status:number,headers:{[string]:string},body:string,bytes:number?}} = nil :: any
local db: {query: ({query:string,params:{any}?,max_rows:number?,read_only:boolean?}) -> any} = nil :: any
local fs: {read:(string)->string,write:(string,string)->(),stat:(string)->{size:number,isFile:boolean},signedGetUrl:(string,number?)->string} = nil :: any
local json: {encode:(any)->string,decode:(string)->any,jq:(any,string)->any} = nil :: any
local houston: {fail:(any)->never} = nil :: any
local require: (string)->any = nil :: any
`

func Check(ctx context.Context, binary string, m manifest.Manifest, modules map[string]string) error {
	if binary == "" {
		binary = "luau-analyze"
	}
	definitions, err := interfaces.Resolve(m.Implements)
	if err != nil {
		return err
	}
	directory, err := os.MkdirTemp("", "houston-analysis-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(directory)
	entrypoints := map[string]bool{}
	for _, file := range m.Files {
		entrypoints[file] = true
	}
	names := make([]string, 0, len(modules))
	for name := range modules {
		names = append(names, name)
	}
	sort.Strings(names)
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	for index, name := range names {
		source := modules[name]
		for _, line := range strings.Split(source, "\n") {
			if strings.HasPrefix(strings.TrimSpace(line), "--!nocheck") || strings.HasPrefix(strings.TrimSpace(line), "--!nonstrict") {
				return fmt.Errorf("%s: disabling publication type analysis is forbidden", name)
			}
		}
		var generated strings.Builder
		generated.WriteString(hosts)
		generated.WriteString(configType(m.Config))
		generated.WriteString("\nlocal exported = (function()\n")
		generated.WriteString(source)
		generated.WriteString("\nend)()\n")
		if entrypoints[name] {
			for _, definition := range definitions {
				keys := make([]string, 0, len(definition.Operations))
				for key := range definition.Operations {
					keys = append(keys, key)
				}
				sort.Strings(keys)
				for _, key := range keys {
					operation := definition.Operations[key]
					args := make([]string, len(operation.Arguments))
					for i, arg := range operation.Arguments {
						args[i] = typeName(arg)
					}
					fmt.Fprintf(&generated, "if exported.%s ~= nil then local _contract: (%s) -> %s = exported.%s end\n", key, strings.Join(args, ","), typeName(operation.Result), key)
				}
			}
		}
		generated.WriteString("return exported\n")
		path := filepath.Join(directory, fmt.Sprintf("module-%d.luau", index))
		if err := os.WriteFile(path, []byte(generated.String()), 0600); err != nil {
			return err
		}
		cmd := exec.CommandContext(ctx, binary, path)
		cmd.Env = []string{"PATH=" + os.Getenv("PATH"), "LANG=C", "HOME=" + directory}
		output := &boundedOutput{}
		cmd.Stdout = output
		cmd.Stderr = output
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("%s: Luau type analysis failed: %s", name, strings.ReplaceAll(string(output.data), directory, "bundle"))
		}
	}
	return nil
}
func configType(fields map[string]manifest.Field) string {
	keys := make([]string, 0, len(fields))
	for key, field := range fields {
		if field.Type != "secret" {
			keys = append(keys, key)
		}
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys))
	for _, key := range keys {
		field := fields[key]
		kind := field.Type
		if kind == "integer" {
			kind = "number"
		}
		if len(field.Options) > 0 {
			options := make([]string, len(field.Options))
			for i, option := range field.Options {
				options[i] = strconv.Quote(option.Value)
			}
			kind = "(" + strings.Join(options, " | ") + ")"
		}
		if field.If != "" || !field.Required && field.Default == nil {
			kind += "?"
		}
		parts = append(parts, "["+strconv.Quote(key)+"]:"+kind)
	}
	return "local config: {" + strings.Join(parts, ",") + "} = nil :: any\n"
}
func typeName(t interfaces.Type) string {
	var value string
	switch t.Kind {
	case "integer":
		value = "number"
	case "array":
		value = "{" + typeName(*t.Element) + "}"
	case "object":
		keys := make([]string, 0, len(t.Fields))
		for key := range t.Fields {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		parts := make([]string, 0, len(keys))
		for _, key := range keys {
			parts = append(parts, "["+strconv.Quote(key)+"]:"+typeName(t.Fields[key]))
		}
		value = "{" + strings.Join(parts, ",") + "}"
	default:
		value = t.Kind
	}
	if t.Optional {
		value += "?"
	}
	return value
}

type boundedOutput struct{ data []byte }

func (b *boundedOutput) Write(p []byte) (int, error) {
	n := len(p)
	remaining := (64 << 10) - len(b.data)
	if remaining > 0 {
		if len(p) > remaining {
			p = p[:remaining]
		}
		b.data = append(b.data, p...)
	}
	return n, nil
}
