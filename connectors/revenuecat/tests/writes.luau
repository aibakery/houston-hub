return {
	scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "sk_fixture"}},
	configure = function()
		requests = {}
		status = 200
		payload = "{}"
		http = {request = function(req)
			table.insert(requests, req)
			return fixture.operation({statusCode = status, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(revenuecat)
		local P = "https://api.revenuecat.com/v2/projects/proj1ab2c3d4"
		local NULL = json.decode("null")
		local function last() return requests[#requests] end
		local function sent(method, target, body)
			local req = last()
			assert(req.method == method and req.url == target, req.method .. " " .. req.url)
			assert(req.headers.Authorization == nil and req.headers.Accept[1] == "application/json")
			if body == nil then
				assert(req.body == nil and req.headers["Content-Type"] == nil, "unexpected body " .. tostring(req.body))
			else
				assert(req.headers["Content-Type"][1] == "application/json")
				assert(req.body == body or json.encode(json.decode(req.body)) == json.encode(body), req.body)
			end
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
		assert(table.concat(names, ",") == "attachPackageProducts,createOffering,createPackage,deletePackage,detachPackageProducts,getApp,getCustomer,getEntitlement,getOffering,getOverviewMetrics,getPackage,getProduct,getPurchase,getSubscription,grantEntitlement,listApps,listCustomerActiveEntitlements,listCustomerPurchases,listCustomerSubscriptions,listCustomers,listEntitlementProducts,listEntitlements,listOfferings,listPackageProducts,listPackages,listProducts,listProjects,listSubscriptionEntitlements,revokeGrantedEntitlement,updateOffering,updatePackage",
			"wrong read-write surface: " .. table.concat(names, ","))

		status, payload = 201, '{"object":"customer","id":"user-1","active_entitlements":{"object":"list","items":[{"object":"customer.active_entitlement","entitlement_id":"entl1","expires_at":1793143768000}],"next_page":null,"url":"/v2/x"}}'
		local granted = revenuecat.grantEntitlement({project_id = "proj1ab2c3d4", customer_id = "user-1", entitlement_id = "entl1", expires_at = 1793143768000})
		sent("POST", P .. "/customers/user-1/actions/grant_entitlement", {entitlement_id = "entl1", expires_at = 1793143768000})
		assert(string.find(last().body, "\"expires_at\":1793143768000", 1, true), "expires_at must be sent as an integer: " .. last().body)
		assert(granted.active_entitlements.items[1].expires_at == 1793143768000)
		status, payload = 200, '{"object":"customer","id":"user-1","active_entitlements":{"object":"list","items":[],"next_page":null,"url":"/v2/x"}}'
		local revoked = revenuecat.revokeGrantedEntitlement({project_id = "proj1ab2c3d4", customer_id = "user-1", entitlement_id = "entl1"})
		sent("POST", P .. "/customers/user-1/actions/revoke_granted_entitlement", {entitlement_id = "entl1"})
		assert(json.encode(revoked.active_entitlements.items) == "[]")

		status, payload = 201, '{"object":"offering","id":"ofrng1","lookup_key":"spring","is_current":false,"metadata":null}'
		local created = revenuecat.createOffering({project_id = "proj1ab2c3d4", lookup_key = "spring", display_name = "Spring sale", metadata = {color = "green"}})
		sent("POST", P .. "/offerings", {lookup_key = "spring", display_name = "Spring sale", metadata = {color = "green"}})
		assert(created.id == "ofrng1" and created.metadata == NULL)
		status, payload = 200, '{"object":"offering","id":"ofrng1","is_current":true}'
		assert(revenuecat.updateOffering({project_id = "proj1ab2c3d4", offering_id = "ofrng1", is_current = true}).is_current == true)
		sent("POST", P .. "/offerings/ofrng1", {is_current = true})

		status, payload = 201, '{"object":"package","id":"pkge1","lookup_key":"$rc_monthly","position":1}'
		revenuecat.createPackage({project_id = "proj1ab2c3d4", offering_id = "ofrng1", lookup_key = "$rc_monthly", display_name = "Monthly", position = 1})
		sent("POST", P .. "/offerings/ofrng1/packages", {lookup_key = "$rc_monthly", display_name = "Monthly", position = 1})
		status, payload = 200, '{"object":"package","id":"pkge1","position":2}'
		revenuecat.updatePackage({project_id = "proj1ab2c3d4", package_id = "pkge1", position = 2})
		sent("POST", P .. "/packages/pkge1", {position = 2})
		revenuecat.attachPackageProducts({project_id = "proj1ab2c3d4", package_id = "pkge1", products = {{product_id = "prod1", eligibility_criteria = "all"}}})
		sent("POST", P .. "/packages/pkge1/actions/attach_products", {products = {{product_id = "prod1", eligibility_criteria = "all"}}})
		revenuecat.detachPackageProducts({project_id = "proj1ab2c3d4", package_id = "pkge1", product_ids = {"prod1"}})
		sent("POST", P .. "/packages/pkge1/actions/detach_products", {product_ids = {"prod1"}})
		payload = '{"object":"package","id":"pkge1","deleted_at":1658399423658}'
		assert(revenuecat.deletePackage({project_id = "proj1ab2c3d4", package_id = "pkge1"}).deleted_at == 1658399423658)
		sent("DELETE", P .. "/packages/pkge1", nil)
		status, payload = 204, ""
		assert(revenuecat.deletePackage({project_id = "proj1ab2c3d4", package_id = "pkge2"}).success == true)
		sent("DELETE", P .. "/packages/pkge2", nil)
		assert(#requests == 10)

		rejected(function() revenuecat.grantEntitlement({project_id = "proj1ab2c3d4", customer_id = "user-1", entitlement_id = "entl1"}) end, "expires_at is required")
		rejected(function() revenuecat.grantEntitlement({project_id = "proj1ab2c3d4", entitlement_id = "entl1", expires_at = 1}) end, "customer_id is required")
		rejected(function() revenuecat.grantEntitlement({project_id = "proj1ab2c3d4", customer_id = "u", entitlement_id = "entl1", expires_at = 1, duration = "P1M"}) end,
			"grantEntitlement has no option duration")
		rejected(function() revenuecat.revokeGrantedEntitlement({project_id = "proj1ab2c3d4", customer_id = "u", entitlement_id = NULL}) end, "entitlement_id is required")
		rejected(function() revenuecat.createOffering({project_id = "proj1ab2c3d4", lookup_key = "spring"}) end, "display_name is required")
		rejected(function() revenuecat.updateOffering({project_id = "proj1ab2c3d4", offering_id = "ofrng1", lookup_key = "new"}) end, "updateOffering has no option lookup_key")
		rejected(function() revenuecat.attachPackageProducts({project_id = "proj1ab2c3d4", package_id = "pkge1"}) end, "products is required")
		rejected(function() revenuecat.deletePackage({project_id = "proj1ab2c3d4", package_id = "a/b"}) end, "package_id must be a RevenueCat id")
	end,
}
