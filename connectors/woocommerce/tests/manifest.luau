return {
	contract = function(m)
		-- TestWooCommerceStoreHostAndAccessBoundaries
		do
			local keys = { consumer_key = "ck_fixture", consumer_secret = "cs_fixture" }
			for _, host in { "", "https://shop.example.com", "shop.example.com/store", "*.example.com" } do
				do
					local _, err = m.resolve(nil, { store_host = host }, keys, "keys")
					if err == nil then
						m.fail("accepted store domain %s", host)
					end
				end
			end
			local basic = "Basic " .. m.base64("ck_fixture:cs_fixture")
			for _, access in { "read-only", "read-write" } do
				local r, err =
					m.resolve(nil, { access = access, store_host = "Shop.Example.com" }, keys, "keys")
				assert(not err, tostring(err))
				if (r.PublicConfig["store_host"] ~= "Shop.Example.com") or (m.count(r.PublicConfig) ~= 2) then
					m.fail("unexpected Lua config: %s", r.PublicConfig)
				end
				local assertRoute = function(method, url, allowed)
					local caller = { Authorization = { "forged" } }
					local recipe, err = m.recipe(r, method, url, caller)
					if not allowed then
						if err == nil then
							m.fail("access=%s allowed %s %s", access, method, url)
						end
						return
					end
					assert(not err, tostring(err))
					local headers, err = m.prepare(recipe, r.Context, caller)
					if
						((err ~= nil) or (m.header(headers, "Authorization") ~= basic))
						or (m.header(caller, "Authorization") ~= "forged")
					then
						m.fail("incorrect credential injection: %s", err)
					end
					m.rejectPreparedOverrides(recipe, r.Context, method .. " " .. url)
				end
				local api = "https://shop.example.com/wp-json/wc/v3"
				for _, path in
					{
						"/orders?status%5B%5D=processing",
						"/orders/1/notes",
						"/orders/1/actions/email_templates",
						"/refunds",
						"/products/1/variations",
						"/products/attributes/1/terms",
						"/customers/1/downloads",
						"/coupons",
						"/taxes/classes",
						"/shipping/zones/0/methods",
						"/shipping_methods",
						"/system_status",
						"/system_status/tools",
						"/reports",
						"/reports/sales",
						"/data/currencies/current",
					}
				do
					assertRoute("GET", api .. path, true)
				end
				for _, path in
					{
						"/settings",
						"/settings/general/woocommerce_currency",
						"/payment_gateways",
						"/payment_gateways/stripe",
						"/webhooks/1",
					}
				do
					assertRoute("GET", api .. path, (access == "read-write"))
				end
				for _, route in
					{
						{ "POST", "/orders" },
						{ "PUT", "/orders/1" },
						{ "DELETE", "/products/1?force=true" },
						{ "POST", "/products/batch" },
						{ "PUT", "/system_status/tools/clear_transients" },
					}
				do
					assertRoute(route[1], api .. route[2], (access == "read-write"))
				end
				for _, route in
					{
						{ "PATCH", api .. "/orders/1" },
						{ "GET", "https://shop.example.com/wp-json/wp/v2/users" },
						{ "GET", "https://shop.example.com/wp-json/wc/v2/orders" },
						{ "GET", "https://shop.example.com/wp-admin/" },
						{ "GET", "https://www.shop.example.com/wp-json/wc/v3/orders" },
						{ "GET", "https://shop.example.com.attacker.test/wp-json/wc/v3/orders" },
						{ "GET", "https://shop.example.com:8443/wp-json/wc/v3/orders" },
						{ "GET", "http://shop.example.com/wp-json/wc/v3/orders" },
						{ "GET", api .. "/orders/%2e%2e/%2e%2e/users" },
					}
				do
					assertRoute(route[1], route[2], false)
				end
			end
		end
	end,
}
