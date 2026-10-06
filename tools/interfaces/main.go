// Command interfaces emits the trusted registry for non-Go consumers.
package main
import("encoding/json";"os";"github.com/aibakery/houston-hub/interfaces")
func main(){defs,err:=interfaces.Resolve([]string{"mail.folders@1","files.metadata@1"});if err!=nil{panic(err)};b,err:=json.MarshalIndent(defs,"","  ");if err!=nil{panic(err)};if err:=os.WriteFile("interfaces/registry.json",append(b,'\n'),0644);err!=nil{panic(err)}}
