return {
	scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "sk_fixture"}},
	configure = function()
		requests = {}
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(revenuecat)
		local API = "https://api.revenuecat.com/v2"
		local P = API .. "/projects/proj1ab2c3d4"
		local NULL = json.decode("null")
		local function last() return requests[#requests] end
		local function got(target)
			local req = last()
			assert(req.method == "GET" and req.url == target, req.method .. " " .. req.url)
			assert(req.body == nil and req.headers.Accept[1] == "application/json" and req.headers.Authorization == nil)
		end
		local function rejected(fn, expected)
			local before = #requests
			local ok, err = pcall(fn)
			assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
			assert(#requests == before, "invalid input reached RevenueCat")
		end

		local names = {}
		for name in revenuecat do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "getApp,getCustomer,getEntitlement,getOffering,getOverviewMetrics,getPackage,getProduct,getPurchase,getSubscription,listApps,listCustomerActiveEntitlements,listCustomerPurchases,listCustomerSubscriptions,listCustomers,listEntitlementProducts,listEntitlements,listOfferings,listPackageProducts,listPackages,listProducts,listProjects,listSubscriptionEntitlements",
			"wrong read-only surface: " .. table.concat(names, ","))
		assert(#requests == 0, "initialization reached RevenueCat")

		payload = '{"object":"list","items":[{"object":"project","id":"proj1ab2c3d4","name":"Acme","created_at":1658399423658,"icon_url":null}],"next_page":null,"url":"/v2/projects"}'
		local projects = fixture.example("listProjects")
		got(API .. "/projects")
		assert(projects.items[1].id == "proj1ab2c3d4" and projects.items[1].icon_url == NULL and projects.next == NULL)

		-- next carries next_page's cursor, decoded, and a missing next_page ends the list too.
		payload = '{"object":"list","items":[{"id":"app1"}],"next_page":"/v2/projects/proj1ab2c3d4/apps?limit=1&starting_after=app%241","url":"/v2/projects/proj1ab2c3d4/apps"}'
		local apps = fixture.example("listApps")
		got(P .. "/apps?limit=1")
		assert(apps.next == "app$1" and apps.next_page == "/v2/projects/proj1ab2c3d4/apps?limit=1&starting_after=app%241")
		revenuecat.listApps({project_id = "proj1ab2c3d4", starting_after = apps.next})
		got(P .. "/apps?starting_after=app%241")
		payload = '{"object":"list","items":[],"url":"/v2/projects/proj1ab2c3d4/apps"}'
		local empty = revenuecat.listApps({project_id = "proj1ab2c3d4"})
		assert(json.encode(empty.items) == "[]" and empty.next == NULL)
		payload = '{"object":"app","id":"app1","type":"app_store","app_store":{"bundle_id":"com.acme"}}'
		assert(fixture.example("getApp").app_store.bundle_id == "com.acme")
		got(P .. "/apps/app1")

		-- Customer lists keep only the lean fields, with JSON nulls left as they are.
		payload = '{"object":"list","items":[{"object":"customer","id":"user-1","project_id":"proj1ab2c3d4","first_seen_at":1,"last_seen_at":null,"last_seen_app_version":"1.2","last_seen_country":"FR","last_seen_platform":"iOS","last_seen_platform_version":null,"experiment":{"id":"exp1","name":"Price test","variant":"a"},"attributes":{"items":[{"name":"$email","value":"ada@example.com"}]}}],"next_page":"https://api.revenuecat.com/v2/projects/proj1ab2c3d4/customers?search=ada%40example.com&starting_after=user-1","url":"/v2/projects/proj1ab2c3d4/customers"}'
		local customers = fixture.example("listCustomers")
		got(P .. "/customers?search=ada%40example.com&limit=100")
		local found = customers.items[1]
		assert(found.id == "user-1" and found.last_seen_platform == "iOS" and found.last_seen_at == NULL and found.last_seen_platform_version == NULL)
		assert(customers.next == "user-1")
		local encoded = json.encode(customers.items)
		for _, leaked in {"FR", "Price test", "ada@example.com", "attributes", "experiment"} do
			assert(not string.find(encoded, leaked, 1, true), "customer list kept " .. leaked .. ": " .. encoded)
		end
		payload = '{"object":"list","items":[],"next_page":null,"url":"/v2/projects/proj1ab2c3d4/customers"}'
		assert(json.encode(revenuecat.listCustomers({project_id = "proj1ab2c3d4"}).items) == "[]")

		payload = '{"object":"customer","id":"$RCAnonymousID:abc","last_seen_country":"FR","experiment":null,"active_entitlements":{"object":"list","items":[{"object":"customer.active_entitlement","entitlement_id":"entl1","expires_at":null}],"next_page":null,"url":"/v2/x"}}'
		local one = fixture.example("getCustomer")
		got(P .. "/customers/%24RCAnonymousID%3Aabc?expand=attributes")
		assert(one.last_seen_country == "FR" and one.experiment == NULL and one.active_entitlements.items[1].expires_at == NULL)
		assert(one.next == nil, "single objects get no cursor")

		payload = '{"object":"list","items":[{"object":"subscription","id":"sub1","status":"active","gives_access":true,"ends_at":null}],"next_page":null,"url":"/v2/x"}'
		local subs = fixture.example("listCustomerSubscriptions")
		got(P .. "/customers/user-1/subscriptions?environment=production&expand=items.redemption")
		assert(subs.items[1].status == "active" and subs.items[1].ends_at == NULL)
		fixture.example("listCustomerPurchases")
		got(P .. "/customers/user-1/purchases?environment=sandbox&starting_after=purch1")
		fixture.example("listCustomerActiveEntitlements")
		got(P .. "/customers/user-1/active_entitlements")

		payload = '{"object":"subscription","id":"sub1","pending_changes":null}'
		assert(fixture.example("getSubscription").pending_changes == NULL)
		got(P .. "/subscriptions/sub1?expand=redemption")
		payload = '{"object":"list","items":[],"next_page":null,"url":"/v2/x"}'
		fixture.example("listSubscriptionEntitlements")
		got(P .. "/subscriptions/sub1/entitlements")
		payload = '{"object":"purchase","id":"purch1"}'
		fixture.example("getPurchase")
		got(P .. "/purchases/purch1")

		payload = '{"object":"list","items":[],"next_page":null,"url":"/v2/x"}'
		fixture.example("listProducts")
		got(P .. "/products?app_id=app1&expand=items.app&expand=items.indicative_price")
		fixture.example("listEntitlements")
		got(P .. "/entitlements?expand=items.product")
		fixture.example("listEntitlementProducts")
		got(P .. "/entitlements/entl1/products")
		fixture.example("listOfferings")
		got(P .. "/offerings?expand=items.package&expand=items.package.product")
		fixture.example("listPackages")
		got(P .. "/offerings/ofrng1/packages?expand=items.product")
		fixture.example("listPackageProducts")
		got(P .. "/packages/pkge1/products")
		payload = '{"object":"product","id":"prod1"}'
		fixture.example("getProduct")
		got(P .. "/products/prod1?expand=app")
		fixture.example("getEntitlement")
		got(P .. "/entitlements/entl1")
		fixture.example("getOffering")
		got(P .. "/offerings/ofrng1?expand=package&expand=package.product")
		fixture.example("getPackage")
		got(P .. "/packages/pkge1")

		payload = '{"object":"overview_metrics","currency":"EUR","metrics":[{"object":"overview_metric","id":"mrr","name":"MRR","unit":"€","period":"P28D","value":34765,"last_updated_at":null,"last_updated_at_iso8601":null}]}'
		local overview = fixture.example("getOverviewMetrics")
		got(P .. "/metrics/overview?currency=EUR")
		assert(overview.metrics[1].id == "mrr" and overview.metrics[1].value == 34765 and overview.metrics[1].last_updated_at == NULL)
		assert(#requests == 25)

		rejected(function() revenuecat.listApps() end, "project_id is required")
		rejected(function() revenuecat.listApps({project_id = NULL}) end, "project_id is required")
		rejected(function() revenuecat.getCustomer({project_id = "proj1ab2c3d4", customer_id = "a/b"}) end, "customer_id must be a RevenueCat id")
		rejected(function() revenuecat.getCustomer({project_id = "proj1ab2c3d4", customer_id = "%2e%2e"}) end, "customer_id must be a RevenueCat id")
		rejected(function() revenuecat.getCustomer({project_id = "..", customer_id = "x"}) end, "project_id must be a RevenueCat id")
		rejected(function() revenuecat.getCustomer({project_id = "proj1ab2c3d4", customer_id = 42}) end, "customer_id must be a string")
		rejected(function() revenuecat.listCustomers({project_id = "proj1ab2c3d4", email = "ada@example.com"}) end, "listCustomers has no option email")
		rejected(function() revenuecat.listOfferings({project_id = "proj1ab2c3d4", expand = {}}) end, "expand must not be an empty array")
		rejected(function() revenuecat.listOfferings({project_id = "proj1ab2c3d4", expand = {package = true}}) end, "expand must be an array")
		rejected(function() revenuecat.listProjects("proj1ab2c3d4") end, "opts must be an object")
	end,
}
