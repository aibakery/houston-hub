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
		local API = "https://slides.googleapis.com/v1/presentations/"
		local names = {}
		for name in c do table.insert(names, name) end
		table.sort(names)
		assert(table.concat(names, ",") == "getPage,getPresentation,getPresentationText,getThumbnail", table.concat(names, ","))

		local function text(...)
			local elements = {}
			for _, content in {...} do
				table.insert(elements, {paragraphMarker = {style = {}}})
				table.insert(elements, {textRun = {content = content, style = {}}})
			end
			return {textElements = elements}
		end
		local function shape(id, content)
			return {objectId = id, shape = {shapeType = "TEXT_BOX", text = content}}
		end
		local deck = {presentationId = "1PrE_x-9", title = "Q3", revisionId = "r1", slides = {
			{objectId = "p1", pageElements = {
				shape("title", text("Q3 results\n")),
				{objectId = "pic", image = {contentUrl = "https://lh3.googleusercontent.com/x"}, title = "Chart"},
				{objectId = "grp", elementGroup = {children = {shape("a", text("Revenue up\vagain\n", "Costs flat\n")),
					{objectId = "num", shape = {shapeType = "TEXT_BOX", text = {textElements = {{paragraphMarker = {}}, {autoText = {type = "SLIDE_NUMBER", content = "1"}}, {textRun = {content = "\n"}}}}}}}}},
				{objectId = "tbl", table = {rows = 1, columns = 2, tableRows = {{tableCells = {{text = text("Region\n")}, {text = text("EU\tUS\v", "APAC\n")}, {}}}}}},
				{objectId = "art", wordArt = {renderedText = "WOW"}},
				shape("empty", nil),
			}, slideProperties = {notesPage = {notesProperties = {speakerNotesObjectId = "n1"}, pageElements = {
				shape("n0", text("Slide image\n")), shape("n1", text("Mention the EU launch\n")),
			}}}},
			{objectId = "p2", pageElements = {}, slideProperties = {isSkipped = true, notesPage = {notesProperties = {speakerNotesObjectId = "n2"}, pageElements = {}}}},
			{objectId = "p3"},
		}}
		local fields = url.encode("presentationId,title,revisionId,slides(objectId,pageElements(shape.text.textElements(textRun.content,autoText.content),table.tableRows.tableCells.text.textElements(textRun.content,autoText.content),wordArt.renderedText,elementGroup.children(shape.text.textElements(textRun.content,autoText.content),table.tableRows.tableCells.text.textElements(textRun.content,autoText.content),wordArt.renderedText,elementGroup.children(shape.text.textElements(textRun.content,autoText.content),table.tableRows.tableCells.text.textElements(textRun.content,autoText.content),wordArt.renderedText,elementGroup))),slideProperties(isSkipped,notesPage(notesProperties.speakerNotesObjectId,pageElements(objectId,shape.text.textElements(textRun.content,autoText.content)))))")
		responses = {json.encode(deck), '{"presentationId":"p1","title":"Empty"}'}
		local read = c.getPresentationText({presentationId = "https://docs.google.com/presentation/d/1PrE_x-9/edit#slide=id.p1"})
		assert(requests[1].url == API .. "1PrE_x-9?fields=" .. fields, requests[1].url)
		assert(read.presentationId == "1PrE_x-9" and read.title == "Q3" and read.revisionId == "r1" and #read.slides == 3)
		assert(read.slides[1].objectId == "p1" and read.slides[1].text == "Q3 results\nRevenue up\nagain\nCosts flat\n1\nRegion\tEU US APAC\t\nWOW\n", read.slides[1].text)
		assert(read.slides[1].notes == "Mention the EU launch\n" and read.slides[1].isSkipped == nil, read.slides[1].notes)
		assert(read.slides[2].text == "" and read.slides[2].notes == "" and read.slides[2].isSkipped == true)
		assert(read.slides[3].objectId == "p3" and read.slides[3].text == "" and read.slides[3].notes == "")
		local empty = c.getPresentationText({presentationId = "https://docs.google.com/presentation/u/1/d/p1/edit"})
		assert(empty.title == "Empty" and json.encode(empty.slides) == "[]" and requests[2].url == API .. "p1?fields=" .. fields, requests[2].url)

		responses = {json.encode(deck), '{"presentationId":"p1"}', '{"objectId":"g1","pageType":"SLIDE","pageElements":[]}',
			'{"objectId":"g1","comments":[{"commentId":"c1"}]}', '{"width":800,"height":450,"contentUrl":"https://lh7-us.googleusercontent.com/t"}', '{"width":200,"height":113,"contentUrl":"https://lh7-us.googleusercontent.com/s"}', '{"width":2000,"height":1125,"contentUrl":"https://lh7-us.googleusercontent.com/w"}'}
		assert(c.getPresentation({presentationId = "1PrE_x-9"}).slides[1].objectId == "p1" and requests[3].url == API .. "1PrE_x-9", requests[3].url)
		local none = c.getPresentation({presentationId = "https://docs.google.com/a/example.com/presentation/d/p1/edit", fields = "presentationId,slides.objectId", commentsViewMode = "COMMENTS_VIEW_MODE_INCLUDED"})
		assert(none.slides == nil, "getPresentation changed Google's JSON")
		assert(requests[4].url == API .. "p1?commentsViewMode=COMMENTS_VIEW_MODE_INCLUDED&fields=presentationId%2Cslides.objectId", requests[4].url)
		assert(c.getPage({presentationId = "p1", pageObjectId = "g1"}).pageType == "SLIDE" and requests[5].url == API .. "p1/pages/g1", requests[5].url)
		assert(c.getPage({presentationId = "p1", pageObjectId = "g1", commentsViewMode = "COMMENTS_VIEW_MODE_INCLUDED"}).comments[1].commentId == "c1")
		assert(requests[6].url == API .. "p1/pages/g1?commentsViewMode=COMMENTS_VIEW_MODE_INCLUDED", requests[6].url)
		local thumbnail = c.getThumbnail({presentationId = "p1", pageObjectId = "g1"})
		assert(thumbnail.width == 800 and thumbnail.contentUrl == "https://lh7-us.googleusercontent.com/t" and requests[7].url == API .. "p1/pages/g1/thumbnail", requests[7].url)
		c.getThumbnail({presentationId = "p1", pageObjectId = "SLIDES_API1_0", thumbnailSize = "SMALL"})
		assert(requests[8].url == API .. "p1/pages/SLIDES_API1_0/thumbnail?thumbnailProperties.thumbnailSize=SMALL", requests[8].url)
		assert(c.getThumbnail({presentationId = "p1", pageObjectId = "q3:summary", thumbnailSize = "WIDTH2000_PX"}).width == 2000)
		assert(requests[9].url == API .. "p1/pages/q3%3Asummary/thumbnail?thumbnailProperties.thumbnailSize=WIDTH2000_PX", requests[9].url)
		for _, req in requests do
			assert(req.method == "GET" and req.body == nil, req.method .. " " .. req.url)
			assert(req.headers == nil or req.headers.Authorization == nil, "connector set credentials")
		end

		local sent = #requests
		local invalid = {
			{},
			{presentationId = ""},
			{presentationId = ".."},
			{presentationId = "p/1"},
			{presentationId = "p1 x"},
			{presentationId = "https://docs.google.com/presentation/d/e/2PACX-1vS/pub?start=false"},
			{presentationId = "https://docs.google.com.example.com/presentation/d/p1/edit"},
			{presentationId = "https://example.com/?u=https://docs.google.com/presentation/d/p1"},
			{presentationId = "https://docs.google.com/document/d/d1/edit"},
			{presentationId = "https://docs.google.com/presentation/#d/p1"},
			{presentationId = "p1", key = "api-key"},
		}
		for _, args in invalid do
			assert(not pcall(c.getPresentation, args), "getPresentation accepted " .. json.encode(args))
			assert(not pcall(c.getPresentationText, args), "getPresentationText accepted " .. json.encode(args))
		end
		assert(not pcall(c.getPresentation, "p1"))
		assert(not pcall(c.getPresentationText, {presentationId = "p1", fields = "title"}), "getPresentationText chooses its fields")
		assert(not pcall(c.getPresentationText, {presentationId = "p1", commentsViewMode = "COMMENTS_VIEW_MODE_INCLUDED"}))
		assert(not pcall(c.getPage, {presentationId = "p1"}), "getPage requires pageObjectId")
		assert(not pcall(c.getPage, {presentationId = "p1", pageObjectId = ".."}))
		assert(not pcall(c.getPage, {presentationId = "p1", pageObjectId = "g1/thumbnail"}))
		assert(not pcall(c.getThumbnail, {presentationId = "p1", pageObjectId = "g1", thumbnailSize = {"SMALL", "LARGE"}}), "thumbnailSize repeated")
		assert(not pcall(c.getThumbnail, {presentationId = "p1", pageObjectId = "g1", thumbnailSize = "HUGE"}))
		assert(not pcall(c.getThumbnail, {presentationId = "p1", pageObjectId = "g1", ["thumbnailProperties.thumbnailSize"] = "LARGE"}), "dotted size is not an option")
		assert(not pcall(c.getThumbnail, {presentationId = "p1", pageObjectId = "g1", ["thumbnailProperties.mimeType"] = "PNG"}))
		assert(not pcall(c.getThumbnail, {presentationId = "p1", pageObjectId = "g1", extra = true}))
		assert(not pcall(c.getThumbnail, {presentationId = "p1/x", pageObjectId = "g1"}))
		assert(not pcall(c.getPage, {presentationId = "https://docs.google.com/presentation/d/e/2PACX-1vS/pub", pageObjectId = "g1"}))
		assert(not pcall(c.getThumbnail, {presentationId = "p1", pageObjectId = "g1", thumbnailSize = {size = "SMALL"}}))
		assert(not pcall(c.getThumbnail, {presentationId = "p1", pageObjectId = "g1", mimeType = "JPEG"}), "PNG is the only thumbnail type")
		assert(#requests == sent, "invalid input reached Google")
		assert(#responses == 0)
	end,
}
