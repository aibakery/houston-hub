return {
	contract = function(m)
		-- TestPrestaShopStoreHostAndAccessBoundaries
		do
			local key = "0123456789ABCDEF0123456789ABCDEF"
			for _, host in { "", "https://shop.example.com", "shop.example.com/store", "*.example.com" } do
				do
					local _, err = m.resolve(nil, { store_host = host }, { token = key }, "key")
					if err == nil then
						m.fail("accepted store domain %s", host)
					end
				end
			end
			do
				local _, err = m.resolve(nil, { store_host = "shop.example.com" }, { token = "short" }, "key")
				if err == nil then
					m.fail("accepted a key that is not 32 characters")
				end
			end
			local basic = "Basic " .. m.base64(key .. ":")
			local api = "https://shop.example.com/api/"
			for _, access in { "read-only", "read-write" } do
				local r, err = m.resolve(
					nil,
					{ access = access, store_host = "Shop.Example.com" },
					{ token = key },
					"key"
				)
				assert(not err, tostring(err))
				if (r.PublicConfig["store_host"] ~= "Shop.Example.com") or (m.count(r.PublicConfig) ~= 2) then
					m.fail("unexpected Lua config: %s", r.PublicConfig)
				end
				m.routes(r, basic, true, {
					"GET " .. api .. "orders?display=full&limit=0%2C50",
					"GET " .. api .. "orders/1",
					"GET " .. api .. "order_details",
					"GET " .. api .. "order_histories/2",
					"GET " .. api .. "order_slip/3",
					"GET " .. api .. "order_states",
					"GET " .. api .. "order_carriers/4",
					"GET " .. api .. "customers/5",
					"GET " .. api .. "addresses",
					"GET " .. api .. "carts/6",
					"GET " .. api .. "products/7",
					"GET " .. api .. "combinations",
					"GET " .. api .. "categories/8",
					"GET " .. api .. "stock_availables/9",
					"GET " .. api .. "cart_rules",
					"GET " .. api .. "languages",
				})
				m.routes(r, basic, (access == "read-write"), {
					"POST " .. api .. "products",
					"POST " .. api .. "customers",
					"POST " .. api .. "order_histories?sendemail=1",
					"PATCH " .. api .. "products/1",
					"PATCH " .. api .. "customers/1",
					"PATCH " .. api .. "order_carriers/1",
					"PATCH " .. api .. "stock_availables/1",
					"DELETE " .. api .. "products/1",
					"DELETE " .. api .. "customers/1",
				})
				m.routes(r, basic, false, {
					"GET " .. api .. "configurations",
					"GET " .. api .. "translated_configurations",
					"GET " .. api .. "employees/1",
					"GET " .. api .. "shop_urls",
					"GET " .. api .. "images/customizations/1/1",
					"GET " .. api,
					"GET " .. api .. "orders/1/extra",
					"GET https://shop.example.com/webservice/dispatcher.php?url=configurations",
					"PUT " .. api .. "products/1",
					"POST " .. api .. "orders",
					"PATCH " .. api .. "orders/1",
					"DELETE " .. api .. "orders/1",
					"POST " .. api .. "products/1",
					"DELETE " .. api .. "order_histories/1",
					"HEAD " .. api .. "orders",
					"DELETE " .. api .. "products?id=%5B1%2C2%5D",
					"DELETE " .. api .. "customers",
					"GET https://www.shop.example.com/api/orders",
					"GET https://shop.example.com.attacker.test/api/orders",
					"GET https://shop.example.com:8443/api/orders",
					"GET http://shop.example.com/api/orders",
					"GET " .. api .. "orders/%2e%2e/configurations",
				})
			end
		end
	end,
}
