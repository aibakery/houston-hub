-- TLS mode verify-ca trusts only the pasted CA certificate and skips the host name check.
local CA = [[-----BEGIN CERTIFICATE-----
MIIBizCCATGgAwIBAgIUUZi7NGCxGbSs3OHB4dQS1a9pUi0wCgYIKoZIzj0EAwIw
GjEYMBYGA1UEAwwPRXhhbXBsZSBEZW1vIENBMCAXDTI2MTEwMzA2MDY0MFoYDzIx
MjYxMDEwMDYwNjQwWjAaMRgwFgYDVQQDDA9FeGFtcGxlIERlbW8gQ0EwWTATBgcq
hkjOPQIBBggqhkjOPQMBBwNCAATI/yE1WYWuNPmmIUj261YB2ev1y5LpGyLo/gaN
a29K66kUvWKNSDZsHkDrrEXHNHpYPk5h4QP8G8hMP/4BZIEuo1MwUTAdBgNVHQ4E
FgQU5s3Uplu6j/FgCEkbvbrWWgHDF8MwHwYDVR0jBBgwFoAU5s3Uplu6j/FgCEkb
vbrWWgHDF8MwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNIADBFAiBj6IfJ
VlQ/taNheI/sn4McmVv1/0P924pHrGmKDe0/8QIhAKbtQpz1q8WUpaglTkdSdvXx
Q89QH7BqdNjwVmDoqTu8
-----END CERTIFICATE-----
]]
return {
	scenario = {publisher = {}, auth_method = "", auth_config = {}, config = {host = "203.0.113.7", username = "ada@example.com", password = "fixture-password", tls_mode = "verify-ca", ca_certificate = CA}},
	configure = function()
		requests = {}
		imap = {command = function(request)
			table.insert(requests, request)
			return fixture.operation(json.decode("[]"))
		end}
	end,
	run = function(c)
		assert(json.encode(c.listMailFolders()) == "[]" and #requests == 1 and requests[1].command == "list")
	end,
}
