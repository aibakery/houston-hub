package main

import (
	"regexp"
	"slices"
	"testing"
)

const dockerhubManifest = "../../connectors/dockerhub/houston.json"

// The connector reads Docker Hub anonymously, so its one rule must allow exactly the
// endpoint table's reads.
func TestDockerHubRulesMatchTheEndpointTable(t *testing.T) {
	lua, entries := endpointTable(t, "dockerhub")
	base := regexp.MustCompile(`(?m)^local API = "https://hub\.docker\.com([^"]*)"`).FindStringSubmatch(lua)
	if base == nil {
		t.Fatal("connector.luau has no Docker Hub API base")
	}
	var want []string
	for _, entry := range entries {
		if entry.write {
			t.Fatalf("%s %s is a write", entry.method, entry.path)
		}
		want = append(want, base[1]+entry.path)
	}
	rules := parseManifest(t, dockerhubManifest).Proxy
	if len(rules) != 1 || !slices.Equal(rules[0].Match.Method, []string{"GET"}) {
		t.Fatalf("want one GET rule, got %+v", rules)
	}
	got := slices.Clone(rules[0].Match.Path)
	slices.Sort(want)
	slices.Sort(got)
	if !slices.Equal(got, want) {
		t.Fatalf("endpoint paths %v do not match the rule's %v", want, got)
	}
}

func TestDockerHubPublicRoutes(t *testing.T) {
	r, err := parseManifest(t, dockerhubManifest).Resolve(nil, nil, nil, "")
	if err != nil {
		t.Fatal(err)
	}
	const api = "https://hub.docker.com/v2"
	const nginx = api + "/namespaces/library/repositories/nginx"
	assertAuthorizedRoutes(t, r, "", true,
		"GET "+api+"/namespaces/docker/repositories?name=desk&ordering=-pull_count&page=2&page_size=100",
		"GET "+nginx, "GET "+nginx+"/tags?name=alpine&page=3", "GET "+nginx+"/tags/latest",
		"GET "+api+"/namespaces/bitnami/repositories/redis/tags/7.4.2-debian-12-r0")
	// Writes, token minting, account data, legacy routes, other hosts and traversal stay denied.
	assertAuthorizedRoutes(t, r, "", false,
		"HEAD "+nginx, "HEAD "+nginx+"/tags/latest", "DELETE "+nginx+"/tags/latest", "PATCH "+nginx, "POST "+api+"/namespaces/docker/repositories",
		"PATCH "+nginx+"/immutabletags", "POST "+nginx+"/immutabletags/verify", "GET "+nginx+"/tags/",
		"POST "+api+"/auth/token", "POST "+api+"/users/login", "POST "+api+"/users/2fa-login", "GET "+api+"/access-tokens",
		"GET "+api+"/user/", "GET "+api+"/user/orgs/", "GET "+api+"/orgs/docker/members", "GET "+api+"/orgs/docker/groups",
		"GET "+api+"/orgs/docker/access-tokens", "GET "+api+"/auditlogs/docker", "GET "+api+"/scim/2.0/Users",
		"GET "+api+"/repositories/library/nginx/", "DELETE "+api+"/repositories/library/nginx/tags/latest/",
		"PATCH "+api+"/repositories/library/nginx/", "GET "+api+"/search/repositories/?query=nginx",
		"GET "+api+"/namespaces/library/repositories/%2e%2e/tags", "GET "+api+"/namespaces/library%2Fnginx/repositories",
		"GET https://registry-1.docker.io/v2/library/nginx/tags/list", "GET https://auth.docker.io/token?service=registry.docker.io",
		"GET https://api.scout.docker.com/v1/repositories", "GET https://hub.docker.com.example.com/v2/namespaces/docker/repositories",
		"GET https://docker.com/v2/namespaces/docker/repositories", "GET http://hub.docker.com:8080/v2/namespaces/docker/repositories")
}
