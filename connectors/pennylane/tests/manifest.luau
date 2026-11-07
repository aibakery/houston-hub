return {
	contract = function(m)
		-- TestPennylaneAccessRoutes
		do
			local api = "https://app.pennylane.com/api/external/v2"
			for _, access in { "read-only", "read-write" } do
				local r, err = m.resolve(nil, { access = access }, { token = "pennylane-fixture" }, "token")
				assert(not err, tostring(err))
				m.routes(r, "Bearer pennylane-fixture", true, {
					"GET " .. api .. "/me",
					"GET " .. api .. "/customer_invoices?limit=50&filter=%5B%5D",
					"GET " .. api .. "/customer_invoices/42",
					"GET " .. api .. "/customer_invoices/42/invoice_lines",
					"GET " .. api .. "/supplier_invoices/7/payments",
					"GET " .. api .. "/ledger_entry_lines",
					"GET " .. api .. "/trial_balance?period_start=2026-01-01&period_end=2026-03-31",
					"GET " .. api .. "/changelogs/transactions",
					"GET " .. api .. "/webhook_subscriptions",
					"POST " .. api .. "/exports/fecs",
					"GET " .. api .. "/exports/fecs/9",
				})
				m.routes(r, "Bearer pennylane-fixture", (access == "read-write"), {
					"POST " .. api .. "/customer_invoices",
					"PUT " .. api .. "/customer_invoices/42/finalize",
					"POST " .. api .. "/customer_invoices/42/send_by_email",
					"DELETE " .. api .. "/customer_invoices/42",
					"PUT " .. api .. "/customers/12/categories",
					"POST " .. api .. "/file_attachments",
					"POST " .. api .. "/ledger_entry_lines/lettering",
					"DELETE " .. api .. "/ledger_entry_lines/lettering",
					"POST " .. api .. "/webhook_subscriptions",
					"DELETE " .. api .. "/webhook_subscriptions/5",
				})
				m.routes(r, "Bearer pennylane-fixture", false, {
					"POST https://app.pennylane.com/oauth/token",
					"POST https://app.pennylane.com/oauth/revoke",
					"GET https://app.pennylane.com/oauth/authorize",
					"GET https://app.pennylane.com/",
					"GET https://app.pennylane.com/auth/login",
					"GET https://app.pennylane.com/public/invoice/pdf?encrypted_id=x",
					"GET https://app.pennylane.com/rails/active_storage/blobs/redirect/x/invoice.pdf",
					"GET https://app.pennylane.com/api/external/v1/me",
					"POST " .. api .. "/ledger_attachments",
					"PATCH " .. api .. "/customer_invoices/42",
					"DELETE " .. api .. "/customers/12",
					"GET " .. api .. "/companies",
					"GET " .. api .. "/customer_invoices/%2e%2e/me",
					"GET " .. api .. "/customer_invoices/a%2Fb",
					"GET " .. api,
					"GET https://app.pennylane.com.example.com/api/external/v2/me",
					"GET https://api.pennylane.com/api/external/v2/me",
					"GET http://app.pennylane.com:8080/api/external/v2/me",
					"GET https://pennylane.com/api/external/v2/me",
				})
			end
		end
		-- TestPennylaneReadOnlyPostRejectsMethodOverrides
		do
			local r, err = m.resolve(nil, { access = "read-only" }, { token = "pennylane-fixture" }, "token")
			assert(not err, tostring(err))
			local recipe, err =
				m.recipe(r, "POST", "https://app.pennylane.com/api/external/v2/exports/fecs", nil)
			assert(not err, tostring(err))
			m.rejectPreparedOverrides(recipe, r.Context, "export")
			local headers, err = m.prepare(recipe, r.Context, {})
			if (err ~= nil) or (m.header(headers, "Authorization") ~= "Bearer pennylane-fixture") then
				m.fail("export headers %s: %s", headers, err)
			end
		end
	end,
}
