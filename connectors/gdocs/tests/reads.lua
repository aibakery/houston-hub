return {
	scenario = {publisher = {client_id = "fixture-client", client_secret = "fixture-private-secret"}, config = {}, auth_method = "oauth", auth_config = {}},
	config = {access = "read-only"},
	configure = function()
		requests, responses = {}, {}
		http = {request = function(req)
			table.insert(requests, req)
			assert(#responses > 0, "unexpected request: " .. req.url)
			return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(table.remove(responses, 1))})
		end}
	end,
	run = function(c)
		local API = "https://docs.googleapis.com/v1/documents/"
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "getDocument,getDocumentText", table.concat(names, ","))

		local function paragraph(...)
			return {paragraph = {elements = {...}}}
		end
		local function run(content)
			return {textRun = {content = content, textStyle = {}}}
		end
		local document = {documentId = "1DoC_x-9", title = "Plan", revisionId = "r1", tabs = {
			{tabProperties = {tabId = "t.0", title = "Notes", index = 0}, documentTab = {body = {content = {
				{sectionBreak = {}},
				paragraph(run("Plan\n")),
				paragraph(run("Call "), {person = {personProperties = {name = "Ana", email = "ana@example.com"}}}, run(" on "),
					{dateElement = {dateElementProperties = {displayText = "Oct 21, 2026"}}}, run(" about "),
					{richLink = {richLinkProperties = {title = "Budget", uri = "https://docs.google.com/spreadsheets/d/s1"}}},
					{inlineObjectElement = {inlineObjectId = "kix.1"}}, {person = {personProperties = {email = "bo@example.com"}}}, run(" is "),
					{dropdown = {dropdownProperties = {displayValue = "Done", selectedOptionId = "o2"}}}, run("\n")),
				paragraph(run("Line\vbreak \u{E907}chart\n")),
				{tableOfContents = {content = {paragraph(run("Contents\n"))}}},
				{table = {rows = 1, columns = 2, tableRows = {{tableCells = {
					{content = {paragraph(run("Item\n"))}},
					{content = {paragraph(run("Cost\tUSD\n")), paragraph(run("line\v2\n"))}},
				}}}}},
				paragraph(run("\n")),
			}}}, childTabs = {
				{tabProperties = {tabId = "t.1", title = "Appendix", parentTabId = "t.0", nestingLevel = 1, index = 0}, documentTab = {body = {content = {paragraph(run("A\n"))}}}},
			}},
			{tabProperties = {tabId = "t.2", title = "Empty", index = 1}, documentTab = {body = {content = {{sectionBreak = {}}, paragraph(run("\n"))}}}},
		}}
		local tab = "tabProperties,documentTab.body.content(paragraph.elements(textRun.content,person.personProperties,richLink.richLinkProperties,dateElement.dateElementProperties.displayText,dropdown.dropdownProperties.displayValue),table.tableRows.tableCells.content)"
		local fields = url.encode("documentId,title,revisionId,tabs(" .. tab .. ",childTabs(" .. tab .. ",childTabs(" .. tab .. ")))")
		responses = {json.encode(document), json.encode(document), json.encode(document), '{"documentId":"d1","title":"Empty"}'}
		local all = c.getDocumentText({documentId = "https://docs.google.com/document/d/1DoC_x-9/edit?tab=t.0#heading=h.1"})
		assert(requests[1].url == API .. "1DoC_x-9?includeTabsContent=true&suggestionsViewMode=PREVIEW_WITHOUT_SUGGESTIONS&fields=" .. fields, requests[1].url)
		assert(all.documentId == "1DoC_x-9" and all.title == "Plan" and all.revisionId == "r1" and #all.tabs == 3)
		assert(all.tabs[1].text == "Plan\nCall Ana on Oct 21, 2026 about Budgetbo@example.com is Done\nLine\nbreak chart\nItem\tCost USD line 2\n\n", all.tabs[1].text)
		assert(all.tabs[1].tabId == "t.0" and all.tabs[1].title == "Notes" and all.tabs[1].nestingLevel == 0 and all.tabs[1].parentTabId == nil)
		assert(all.tabs[2].tabId == "t.1" and all.tabs[2].parentTabId == "t.0" and all.tabs[2].nestingLevel == 1 and all.tabs[2].text == "A\n")
		assert(all.tabs[3].tabId == "t.2" and all.tabs[3].text == "\n")
		local child = c.getDocumentText({documentId = "https://docs.google.com/document/u/1/d/d1/edit", tabId = "t.1", suggestionsViewMode = "PREVIEW_SUGGESTIONS_ACCEPTED"})
		assert(#child.tabs == 1 and child.tabs[1].text == "A\n")
		assert(requests[2].url == API .. "d1?includeTabsContent=true&suggestionsViewMode=PREVIEW_SUGGESTIONS_ACCEPTED&fields=" .. fields, requests[2].url)
		local ok, err = pcall(c.getDocumentText, {documentId = "d1", tabId = "t.9"})
		assert(not ok and string.find(tostring(err), "t.9 is not a tab", 1, true), tostring(err))
		local empty = c.getDocumentText({documentId = "https://docs.google.com/a/example.com/document/d/d1/edit"})
		assert(empty.title == "Empty" and json.encode(empty.tabs) == "[]" and requests[4].url == API .. "d1?includeTabsContent=true&suggestionsViewMode=PREVIEW_WITHOUT_SUGGESTIONS&fields=" .. fields, requests[4].url)

		responses = {json.encode(document), '{"documentId":"d1","title":"Legacy","body":{"content":[]}}', '{"documentId":"d1","comments":[{"commentId":"c1"}]}'}
		local full = c.getDocument({documentId = "1DoC_x-9"})
		assert(full.tabs[1].childTabs[1].tabProperties.tabId == "t.1" and requests[5].url == API .. "1DoC_x-9?includeTabsContent=true", requests[5].url)
		local legacy = c.getDocument({documentId = "d1", includeTabsContent = false, fields = "title,body"})
		assert(legacy.title == "Legacy" and legacy.tabs == nil, "getDocument changed Google's JSON")
		assert(requests[6].url == API .. "d1?includeTabsContent=false&fields=title%2Cbody", requests[6].url)
		local commented = c.getDocument({documentId = "d1", suggestionsViewMode = "SUGGESTIONS_INLINE", commentsViewMode = "COMMENTS_VIEW_MODE_INCLUDED"})
		assert(commented.comments[1].commentId == "c1")
		assert(requests[7].url == API .. "d1?includeTabsContent=true&suggestionsViewMode=SUGGESTIONS_INLINE&commentsViewMode=COMMENTS_VIEW_MODE_INCLUDED", requests[7].url)
		for _, req in requests do
			assert(req.method == "GET" and req.body == nil, req.method .. " " .. req.url)
			assert(req.headers == nil or req.headers.Authorization == nil, "connector set credentials")
		end

		local sent = #requests
		local invalid = {
			{},
			{documentId = ""},
			{documentId = ".."},
			{documentId = "d/1"},
			{documentId = "d1 x"},
			{documentId = "https://docs.google.com/document/d/e/2PACX-1vR/pub"},
			{documentId = "https://docs.google.com.example.com/document/d/d1/edit"},
			{documentId = "https://example.com/?u=https://docs.google.com/document/d/d1"},
			{documentId = "https://docs.google.com/spreadsheets/d/s1/edit"},
			{documentId = "https://docs.google.com/document/#d/d1"},
			{documentId = "https://docs.google.com/document/d/d1.x/edit"},
			{documentId = "d1", key = "api-key"},
			{documentId = "d1", includeTabsContent = {mode = "all"}},
		}
		for _, args in invalid do
			assert(not pcall(c.getDocument, args), "getDocument accepted " .. json.encode(args))
			assert(not pcall(c.getDocumentText, args), "getDocumentText accepted " .. json.encode(args))
		end
		assert(not pcall(c.getDocument, "d1"))
		assert(not pcall(c.getDocumentText, "d1"))
		assert(not pcall(c.getDocumentText, {documentId = "d1", fields = "title"}), "getDocumentText chooses its fields")
		assert(not pcall(c.getDocumentText, {documentId = "d1", includeTabsContent = false}))
		assert(not pcall(c.getDocumentText, {documentId = "d1", tabId = ""}))
		assert(not pcall(c.getDocumentText, {documentId = "d1", commentsViewMode = "COMMENTS_VIEW_MODE_INCLUDED"}))
		assert(not pcall(c.getDocumentText, {documentId = "d1", suggestionsViewMode = "SUGGESTIONS_INLINE"}), "getDocumentText would mix suggested and current text")
		assert(not pcall(c.getDocumentText, {documentId = "d1", suggestionsViewMode = "DEFAULT_FOR_CURRENT_ACCESS"}))
		assert(#requests == sent, "invalid input reached Google")
		assert(#responses == 0)
	end,
}
