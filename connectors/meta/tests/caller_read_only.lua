return {
	scenario = {publisher = {}, config = {access = "read-write"}, caller_access = "read-only", auth_method = "token", auth_config = {token = "fixture-page-token"}},
	configure = function()
		http = {request = function(req) error("unexpected request: " .. req.url) end}
	end,
	run = function(meta)
		-- A caller without a write grant sees a read-write connection's reads only.
		assert(meta.getPage and meta.listFeed and meta.listConversations)
		for _, name in {"createPost", "deleteObject", "sendMessage", "uploadPhoto", "publishInstagramMedia", "getInstagramPublishingLimit"} do
			assert(meta[name] == nil, name .. " is exported to a read-only caller")
		end
	end,
}
