return {
	contract = function(m)
		local assertDolibarrRoutes = function(r, key, allowed, ...)
			local routes = { ... }
			for _, route in routes do
				local method, url, _ = m.cut(route, " ")
				local recipe, err = m.recipe(r, method, url, nil)
				if (err == nil) ~= allowed then
					m.fail("%s allowed=%s: %s", route, (err == nil), err)
				end
				if err ~= nil then
					continue
				end
				m.rejectPreparedOverrides(recipe, r.Context, route)
				local headers, err = m.prepare(recipe, r.Context, {
					Dolapikey = { "forged" },
					Authorization = { "Bearer forged" },
					Dolapientity = { "2" },
					Cookie = { "http_method=DELETE" },
				})
				if (err ~= nil) or (m.header(headers, "DOLAPIKEY") ~= key) then
					m.fail("credential injection for %s: %s %s", route, headers, err)
				end
				for _, name in { "Authorization", "DOLAPIENTITY", "Cookie" } do
					if m.header(headers, name) ~= "" then
						m.fail("%s kept %s", route, name)
					end
				end
			end
		end
		-- TestDolibarrHostInstallPathAndAccessBoundaries
		do
			local key = "Zx81Kq0PnB2vLm4TcR7wYs9dHf3jGa6E"
			for _, host in { "", "https://erp.example.com", "example.com/dolibarr", "*.example.com" } do
				do
					local _, err = m.resolve(nil, { host = host }, { token = key }, "key")
					if err == nil then
						m.fail("accepted Dolibarr domain %s", host)
					end
				end
			end
			for _, access in { "read-only", "read-write" } do
				local r, err = m.resolve(
					nil,
					{ access = access, host = "ERP.Example.com", install_path = "/dolibarr" },
					{ token = key },
					"key"
				)
				assert(not err, tostring(err))
				if
					(
						(r.PublicConfig["host"] ~= "ERP.Example.com")
						or (r.PublicConfig["install_path"] ~= "/dolibarr")
					) or (m.count(r.PublicConfig) ~= 3)
				then
					m.fail("unexpected Lua config: %s", r.PublicConfig)
				end
				for _, api in
					{
						"https://erp.example.com/api/index.php",
						"https://erp.example.com/dolibarr/api/index.php",
						"https://erp.example.com/dolibarr/htdocs/api/index.php",
					}
				do
					assertDolibarrRoutes(
						r,
						key,
						true,
						"GET " .. api .. "/status",
						"GET " .. api .. "/thirdparties?limit=100&page=0",
						"GET " .. api .. "/thirdparties/12",
						"GET " .. api .. "/contacts/3",
						"GET " .. api .. "/products/9/stock",
						"GET " .. api .. "/warehouses",
						"GET " .. api .. "/stockmovements",
						"GET " .. api .. "/categories/2",
						"GET " .. api .. "/orders/7",
						"GET " .. api .. "/invoices/42/payments",
						"GET " .. api .. "/proposals",
						"GET " .. api .. "/shipments/1",
						"GET " .. api .. "/supplierorders",
						"GET " .. api .. "/supplierinvoices/5/payments",
						"GET " .. api .. "/bankaccounts/1/lines",
						"GET " .. api .. "/bankaccounts/1/balance",
						"GET " .. api .. "/setup/dictionary/payment_types"
					)
					assertDolibarrRoutes(
						r,
						key,
						(access == "read-write"),
						"POST " .. api .. "/thirdparties",
						"PUT " .. api .. "/thirdparties/12",
						"POST " .. api .. "/contacts",
						"PUT " .. api .. "/contacts/3",
						"POST " .. api .. "/products",
						"PUT " .. api .. "/products/9",
						"POST " .. api .. "/stockmovements",
						"POST " .. api .. "/orders",
						"POST " .. api .. "/orders/7/lines",
						"POST " .. api .. "/orders/7/validate",
						"POST " .. api .. "/orders/7/close",
						"POST " .. api .. "/invoices",
						"POST " .. api .. "/invoices/createfromorder/7",
						"POST " .. api .. "/invoices/42/lines",
						"POST " .. api .. "/invoices/42/validate",
						"POST " .. api .. "/invoices/42/payments"
					)
					assertDolibarrRoutes(
						r,
						key,
						false,
						"GET " .. api .. "/login?login=admin&password=x",
						"POST " .. api .. "/login",
						"GET " .. api .. "/users/info",
						"GET " .. api .. "/users/1",
						"GET " .. api .. "/users/1/setGroup/1",
						"GET " .. api .. "/setup/conf/MAIN_MAIL_SMTPS_PW",
						"GET " .. api .. "/setup/company",
						"GET " .. api .. "/documents/download?modulepart=admin_temp",
						"GET " .. api .. "/explorer/swagger.json",
						"GET " .. api .. "/thirdparties/1/generateBankAccountDocument/1/sepamandate",
						"GET " .. api .. "/accountancy/exportdata",
						"GET " .. api .. "/thirdparties/1/bankaccounts",
						"GET " .. api .. "/mailings/clone/1",
						"DELETE " .. api .. "/invoices/42",
						"DELETE " .. api .. "/thirdparties/12",
						"PUT " .. api .. "/thirdparties/12/merge/13",
						"POST " .. api .. "/contacts/3/createUser",
						"PUT " .. api .. "/invoices/42",
						"POST " .. api .. "/invoices/42/settopaid",
						"POST " .. api .. "/thirdparties/12",
						"PUT " .. api .. "/orders/7",
						"HEAD " .. api .. "/invoices",
						"PATCH " .. api .. "/products/9",
						"GET " .. api .. "/invoices/%2e%2e/users/1"
					)
				end
				assertDolibarrRoutes(
					r,
					key,
					true,
					"GET https://erp.example.com/index.php/api/index.php/status"
				)
				assertDolibarrRoutes(
					r,
					key,
					false,
					"GET https://erp.example.com/a/b/c/api/index.php/status",
					"GET https://erp.example.com/api/status",
					"GET https://erp.example.com/index.php",
					"GET https://erp.example.com/api/index.php/",
					"GET https://www.erp.example.com/api/index.php/status",
					"GET https://erp.example.com.attacker.test/api/index.php/status",
					"GET https://erp.example.com:8443/api/index.php/status",
					"GET http://erp.example.com/api/index.php/status"
				)
			end
		end
	end,
}
