-- A CA certificate that isn't PEM is rejected when the connection is set up.
return {
	scenario = {
		publisher = {}, auth_method = "", auth_config = {},
		config = {host = "203.0.113.7", username = "ada@example.com", password = "fixture-password", tls_mode = "verify-ca", ca_certificate = "MIIBizCCATGgAwIBAgIU"},
		settings_error = "config.ca_certificate: must be PEM certificates",
	},
}
