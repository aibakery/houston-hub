return {
	scenario={config={access="read-write"},auth_method="token",auth_config={token="fixture-token"}},
	configure=function()
		fs=fixture.files();requests={}
		local MAIL,SUB,MASKED="urn:ietf:params:jmap:mail","urn:ietf:params:jmap:submission","https://www.fastmail.com/dev/maskedemail"
		local folders={}
		for _,role in {"inbox","trash","junk","drafts","sent","archive"} do table.insert(folders,{id="folder-" .. role,name=role,role=role}) end
		http={request=function(req)
			if req.body~=nil and type(req.body)~="string" then req.body=await(req.body:readAll()) end
			table.insert(requests,req)
			local data
			if req.url=="https://api.fastmail.com/jmap/session" then
				assert(req.method=="GET")
				data={username="me@example.com",primaryAccounts={[MAIL]="account-1",[MASKED]="account-1"},accounts={["account-1"]={name="Me"}},capabilities={[MAIL]={},[SUB]={},[MASKED]={}},
					apiUrl="https://api.fastmail.com/jmap/api/",uploadUrl="https://api.fastmail.com/jmap/upload/{accountId}/",
					downloadUrl="https://www.fastmailusercontent.com/jmap/download/{accountId}/{blobId}/{name}?type={type}"}
			elseif req.url=="https://api.fastmail.com/jmap/upload/account-1/" then
				assert(req.method=="POST" and req.body=="fixture PDF" and req.headers["Content-Type"][1]=="application/pdf")
				data={blobId="uploaded-blob",type="application/pdf",size=11}
			elseif string.find(req.url,"https://www.fastmailusercontent.com/jmap/download/account-1/blob-1/",1,true)==1 then
				assert(req.method=="GET")
				return fixture.operation({statusCode=200,headers={},body=fixture.reader("fixture PDF")})
			else
				assert(req.method=="POST" and req.url=="https://api.fastmail.com/jmap/api/",req.url)
				local invocation=json.decode(req.body).methodCalls[1]
				local name,args=invocation[1],invocation[2]
				assert(args.accountId=="account-1" and invocation[3]=="0")
				local result={}
				if name=="Mailbox/get" then result={list=folders}
				elseif name=="Identity/get" then result={list={{id="identity-1",email="me@example.com",name="Me"}}}
				elseif name=="MaskedEmail/get" then result={list={{id="masked-1",email="masked@example.com",state="enabled",description="Shopping",forDomain="example.com"}}}
				elseif name=="Email/query" then
					assert(args.limit==20 and args.position==0 and args.calculateTotal==true)
					assert(args.sort[1].property=="receivedAt" and args.sort[1].isAscending==false)
					assert(json.encode(args.filter)==json.encode({operator="AND",conditions={{from="sender@example.com"},{after="2026-11-01T00:00:00Z"},{inMailbox="folder-inbox"}}}))
					result={ids={"message-1","message-2"},position=0,total=2}
				elseif name=="Thread/get" then result={list={{id=args.ids[1],emailIds={"message-1","message-2"}}}}
				elseif name=="Email/get" then
					local list={}
					for _,id in args.ids do table.insert(list,{id=id,threadId="thread-1",from={{email="sender@example.com"}},to={{email="me@example.com"},{email="colleague@example.com"}},subject="Invoice",messageId={"native-message@example.com"},
						textBody={{partId="text",type="text/plain"}},htmlBody={{partId="html",type="text/html"}},bodyValues={text={value="Hello"},html={value="<p>Hello</p>"}},
						attachments={{blobId="blob-1",name="invoice.pdf",type="application/pdf",size=11,disposition="attachment"}}}) end
					result={list=list}
				elseif name=="Email/set" then
					if args.create then
						local draft=args.create.draft
						assert(draft.mailboxIds["folder-drafts"] and draft.keywords["$draft"])
						assert(draft.from[1].email=="me@example.com" and type(draft.bodyValues.text.value)=="string")
						assert(draft.textBody[1].type=="text/plain" and #draft.to>0)
						result={created={draft={id="draft-1"}}}
					elseif args.update then
						local updated={};for id,patch in args.update do assert(next(patch));updated[id]=json.decode("null") end
						result={updated=updated}
					else assert(args.destroy);result={destroyed=args.destroy} end
				elseif name=="EmailSubmission/set" then
					assert(args.create.send.emailId=="draft-1" and args.create.send.identityId=="identity-1")
					assert(args.onSuccessUpdateEmail["#send"].mailboxIds["folder-sent"] and args.onSuccessUpdateEmail["#send"].keywords["$seen"])
					result={created={send={id="submission-1"}}}
				elseif name=="Mailbox/set" then
					assert(type(args.create.folder.name)=="string")
					result={created={folder={id="new-folder",name=args.create.folder.name}}}
				else error("unexpected JMAP method " .. name) end
				data={methodResponses={{name,result,"0"}}}
			end
			return fixture.operation({statusCode=200,headers={},body=fixture.reader(json.encode(data))})
		end}
	end,
	run=function(c)
		local file=fs.open("receipt.pdf","w");file:write("fixture PDF");await(file:close())
		local variants={getMessage=true,getMessages=true,getThread=true,getAttachment=true,getAttachments=true,markRead=true,markUnread=true,deleteMessage=true,deleteMessages=true,
			destroyMessage=true,destroyMessages=true,archiveMessage=true,archiveMessages=true,moveMessage=true,moveMessages=true,createFolder=true,replyMessage=true}
		local count=0
		for name in c do
			if name~="help" then
				count+=1
				for index=1,(if variants[name] then 2 else 1) do
					local before=#requests
					local result=fixture.example(name,index)
					assert(type(result)=="table",name)
					assert(#requests>before or name=="getProfile",name)
					local calls={}
					for n=before+1,#requests do
						local req=requests[n]
						if req.url=="https://api.fastmail.com/jmap/api/" then
							local invocation=json.decode(req.body).methodCalls[1];calls[invocation[1]]=invocation[2]
						end
					end
					if name=="sendMessage" then
						local draft=calls["Email/set"].create.draft
						assert(draft.to[1].email=="recipient@example.com" and draft.attachments[1].blobId=="uploaded-blob")
						assert(result.id=="draft-1" and result.submissionId=="submission-1")
					elseif name=="replyMessage" then
						local draft=calls["Email/set"].create.draft
						assert(draft.to[1].email=="sender@example.com" and draft.cc[1].email=="colleague@example.com")
						assert(draft.inReplyTo[1]=="native-message@example.com" and draft.references[1]=="native-message@example.com" and draft.subject=="Re: Invoice")
					elseif name=="markRead" or name=="markUnread" then
						assert(calls["Email/set"].update["message-1"]["keywords/$seen"]==(if name=="markRead" then true else json.decode("null")))
					elseif string.match(name,"^destroy") then assert(calls["Email/set"].destroy[1]=="message-1")
					elseif string.match(name,"^archive") then assert(result.folderId=="folder-archive")
					elseif string.match(name,"^delete") then assert(result.folderId=="folder-trash")
					elseif string.match(name,"^move") then assert(result.folderId==(if index==1 then "folder-inbox" else "folder-archive"))
					elseif name=="getMessage" then assert(result.body=="Hello" and calls["Email/get"].maxBodyValueBytes==(if index==1 then 4096 else nil))
					elseif name=="getMessages" then assert(result[1].id=="message-1" and result[1].body==(if index==1 then "Hello" else "<p>Hello</p>"))
					elseif name=="getThread" then assert(result.id=="thread-1" and #result.messages==2)
					elseif name=="getAttachment" then assert(result.size==11 and type(result.url)=="string" and await(fs.stat(result.path)).size==11)
					elseif name=="getAttachments" then assert(#result==1 and result[1].size==11)
					end
				end
			end
		end
		assert(count==27,tostring(count))
	end,
}
