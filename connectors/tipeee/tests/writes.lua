local requests = {}
local payload = "{}"
local status = 200
return {
	scenario = {config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-token"}},
	configure = function()
		requests = {}; payload = "{}"; status = 200
		fs = fixture.files()
		local multipart = http.multipart
		http = {multipart = multipart, request = function(req)
			assert(req.headers.Authorization == nil and not string.find(req.url, "access_token", 1, true))
			if req.body ~= nil and type(req.body) ~= "string" then req.body = await(req.body:readAll()) end
			table.insert(requests, req)
			return fixture.operation({statusCode = status, headers = {}, body = fixture.reader(payload)})
		end}
	end,
	run = function(t)
		local function last() return requests[#requests] end
		local function form(method, suffix, fields)
			local req = last()
			assert(req.method == method and req.url == "https://api.tipeee.com" .. suffix, req.url)
			assert(string.find(req.headers["Content-Type"][1], "multipart/form-data; boundary=", 1, true))
			for key, value in fields do
				assert(string.find(req.body, 'name="' .. key .. '"\r\n\r\n' .. value .. '\r\n', 1, true), "missing form " .. key)
			end
		end
		local writes = "getMe getProject listProjects listInboxProjects listInboxThreads getInboxThread listMessages blockTipper cloneReward configureAlertsWidget configureGoalsWidget configureLastsWidget configureTotalsWidget createComment createGoal createNews createOneOffProject createProject createReward deleteComment deleteGoal deleteNews deleteThread disconnectDiscord downloadTippers emailTippersExport enableStreaming findOrCreateThread followThread getWidgets lockThread renameThread replayStreamAlert requestPayout sendMessage transitionReward unblockTipper unfollowThread unlockThread updateCampaign updateGoal updateNews updateProject updateProjectAvatar updateProjectCover updateProjectDescription updateProjectLinks updateProjectSettings updateReward uploadMedia uploadMessageFileChunk"
		local reads = "downloadMedia downloadPaymentBill downloadPaymentTips downloadPayments downloadPrivateMedia getCampaignRewardStats getCloseDate getDiscordGuild getNews getPayoutState getRecurringIndicators getReward getStatistics getUnreadMessages getWidgetGoal listCampaignRewards listCampaigns listCategories listComments listNews listPayments listRewards listTippers searchMessageTippers"
		local expected = {}
		for name in string.gmatch(reads .. " " .. writes, "%S+") do expected[name] = true; assert(type(t[name]) == "function", name) end
		for name in t do assert(expected[name], "unexpected export " .. name) end
		payload = '{"id":7,"projects":[{"slug":"my-art","api_key":"secret"}]}'
		assert(t.getMe().projects[1].api_key == nil)
		t.listProjects({q="art & music",mode="search",lang="en"})
		assert(last().url == "https://api.tipeee.com/v2.0/projects?q=art%20%26%20music&mode=search&lang=en")
		payload = '[{"id":3,"token":"older-cursor"}]'
		assert(t.listMessages({threadToUser=19,token="a+b?"})[1].token == "older-cursor")
		assert(last().url == "https://api.tipeee.com/v2.0/inbox/threads/19/content?token=a%2Bb%3F")
		payload = "{}"
		local project = {translations={en={name="My art"}},slug="my-art",lang="en",categories={1,3}}
		t.createProject({data=project})
		form("POST","/v2.0/projects",{["translations[en][name]"]="My art",slug="my-art",lang="en",["categories[0]"]="1",["categories[1]"]="3"})
		t.updateProjectDescription({project="my-art",data={translations={en={html="<p>About</p>"}}}})
		form("POST","/v2.0/projects/my-art/contents",{["translations[en][html]"]="<p>About</p>"})
		local reward = {price=10,translations={en={name="Print",description_v2="<p>A print</p>"}},modules={stock={available={unlimited=false,quantity=5}},custom={settings={{name="Size",options={{name="Small",is_additional_config=false},{name="Large",is_additional_config=false}}}}}}}
		t.updateReward({project="my-art",reward=12,data=reward})
		form("POST","/v2.0/projects/my-art/rewards/12",{_method="put",price="10",["modules[stock][available][unlimited]"]="false",["modules[custom][settings][0][options][1][name]"]="Large"})
		assert(reward._method == nil)
		t.createNews({project="my-art",data={name="Update",contentv2={translations={en={html="<p>Hello</p>"}}},draft=true}})
		form("POST","/v2.0/projects/my-art/news",{name="Update",draft="true",["contentv2[translations][en][html]"]="<p>Hello</p>"})
		t.updateNews({project="my-art",news=2,data={draft=false,parameters={tip_content=1,private_type="rewards",private_rule_rewards={12}}}})
		form("POST","/v2.0/projects/my-art/news/2",{_method="put",draft="false",["parameters[tip_content]"]="1",["parameters[private_rule_rewards][0]"]="12"})
		t.transitionReward({project="my-art",reward=12,data={transition="archive"}})
		assert(last().method == "PUT" and last().url == "https://api.tipeee.com/v2.0/projects/my-art/rewards/12/transition" and json.decode(last().body).transition == "archive")
		t.cloneReward({project="my-art",reward=12})
		assert(last().method == "PUT" and last().body == "{}")
		t.sendMessage({data={action="CREATE",content="Hello",title="Update",project=7,rules={campaign="2026-10",rewards={12}},attachments=json.decode("[]")}})
		local message = json.decode(last().body)
		assert(last().url == "https://api.tipeee.com/v2.0/inbox/contents" and message.action == "CREATE" and message.rules.rewards[1] == 12 and json.encode(message.attachments) == "[]")
		t.sendMessage({data={action="RESPONSE",content="Reply",thread=4}})
		assert(json.decode(last().body).thread == 4)
		t.createComment({thread="news-permalink",data={body="Hi",parent=8}})
		form("POST","/v2.0/threads/news-permalink/comments",{body="Hi",parent="8"})
		payload = ""; status = 204
		assert(t.deleteComment({thread="news-permalink",comment=9}).status == "success")
		assert(last().method == "DELETE" and last().body == nil)
		assert(t.requestPayout({project="my-art"}).status == "success")
		assert(last().method == "PUT" and last().url == "https://api.tipeee.com/v2.0/projects/my-art/payout" and last().body == nil)
		payload = '{"alerts":{"url":"https://widgets.tipeee.com/private-link"}}'; status = 200
		assert(t.getWidgets({project="my-art"}).alerts.url == "https://widgets.tipeee.com/private-link")
		t.configureGoalsWidget({project="my-art",data={name="Target",goal_amount=100,initial_amount=0}})
		form("POST","/v2.0/projects/my-art/widgets/goals",{name="Target",goal_amount="100",initial_amount="0"})
		local before = #requests
		for _, data in {{action="CREATE",content="missing"},{action="DELETE",content="bad"},{action="RESPONSE",content="missing-thread"},{action="ERRATUM",content="missing-parent",thread=1}} do
			assert(not pcall(function() t.sendMessage({data=data}) end))
		end
		assert(not pcall(function() t.createNews({project="p",data={name="No decision",contentv2={}}}) end))
		assert(not pcall(function() t.updateProject({project="p",data={_method="delete"}}) end))
		assert(not pcall(function() t.blockTipper({username="u",data={target=1,status="ADMIN"}}) end))
		assert(not pcall(function() t.updateProjectAvatar({project="p",files={_method={path="a",filename="a",contentType="image/png"}}}) end))
		assert(not pcall(function() t.createComment({thread="p",data={body=string.rep("a",1025)}}) end))
		assert(not pcall(function() t.createComment({thread="p",data={body=string.char(255)}}) end))
		assert(#requests == before, "invalid mutation reached network")
		payload = "{}"
		t.createComment({thread="p",data={body=string.rep("é",1024)}})
		form("POST","/v2.0/threads/p/comments",{body=string.rep("é",1024)})
	end,
}
