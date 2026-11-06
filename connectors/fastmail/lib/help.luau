-- Schemas describe this connector's normalized mail interface, including its
-- established positional overloads. Native JMAP transport stays in connector.luau.
local function text(description: string?): any return {type="string",description=description} end
local function object(properties: any,required: any?): any return {type="object",properties=properties,required=required or json.decode("[]"),additionalProperties=false} end
local function array(items: any,minimum: number?,maximum: number?): any return {type="array",items=items,minItems=minimum,maxItems=maximum} end
local function either(...: any): any return {anyOf={...}} end
local ID: any={type="string",minLength=1,description="Opaque provider ID; folder arguments also accept a role such as INBOX."}
local row=object({id=ID},{"id"})
local id=either(ID,row)
local ids=either(id,array(id,1))
local path: any={type="string",minLength=1,description="Private session file path."}
local address=object({email={type="string",minLength=1,format="email"},name=text()},{"email"})
local upload=either(path,object({path=path,filename=text("Defaults to the path basename."),mimeType={type="string",minLength=1,default="application/octet-stream"}},{"path"}))
local downloadItem=either(ID,object({id=ID,path=path},{"id"}))
local download=object({path=path,url={type="string",format="uri",description="Expiring signed Houston URL."},size={type="integer",minimum=0}},{"path","url"})
local moved=object({ids=array(ID),folderId=ID},{"ids","folderId"})
local confirmed=object({ids=array(ID)},{"ids"})
local sent=object({id=ID,submissionId=ID},{"id","submissionId"})
local attachment=object({id=ID,filename=text(),mimeType=text(),size={type="integer",minimum=0},inline={type="boolean"},contentId=text()},{"id","inline"})
local envelope: any={type="object",properties={id=ID,threadId=ID,from=text(),to=text(),cc=text(),bcc=text(),replyTo=text(),subject=text(),date=text(),messageId=text(),
	body=text(),bodyTruncated={type="boolean"},attachments=array(attachment),received=array(text()),headers=array(object({name=text(),value=text()},{"name","value"})),
	mailboxIds={type="object",additionalProperties={type="boolean"}},keywords={type="object",additionalProperties={type="boolean"}},preview=text()},required={"id","body","attachments","received"}}
local function fields(base: any,extra: any): any local p=table.clone(base);for k,v in extra do p[k]=v end;return p end
local function namedOrPositional(named: any,positional: any): any return {anyOf={named,positional}} end
return function(descriptions: any,functions: any,batchSize: number,defaultBodyBytes: number,defaultPageSize: number,maxPageSize: number): any
	local docs={}
	local function add(name: string,schema: any,examples: any,args: any?,output: any?)
		schema.examples=examples
		docs[name]={description=assert(descriptions[name],"missing help " .. name),inputSchema=schema,args=args,outputSchema=output,
			annotations={readOnlyHint=not (string.match(name,"^mark") or string.match(name,"^archive") or string.match(name,"^move") or string.match(name,"^delete") or string.match(name,"^destroy") or string.match(name,"^trash") or name=="sendMessage" or name=="replyMessage" or name=="createFolder")}}
	end
	local empty=json.decode("{}")
	local bodyProperties={maxBodyValueBytes={type="integer",minimum=0,default=defaultBodyBytes,description="Per-part byte cap; zero disables the cap."},bodyFormat={enum={"auto","text","html"},default="auto"}}
	local body=object(bodyProperties)
	local date={type="string",pattern="^[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z)?$",description="YYYY-MM-DD (midnight UTC) or a UTC timestamp."}
	local searchProperties={from=either(text(),array(text())),to=either(text(),array(text())),subject=either(text(),array(text())),text=either(text(),array(text())),
		alias=either({type="string",minLength=1},array({type="string",minLength=1})),aliases=array({type="string",minLength=1}),folder=either(ID,array(ID)),folders=array(ID),after=date,before=date,
		includeSpamTrash={type="boolean",default=false},maxResults={type="integer",minimum=1,maximum=maxPageSize,default=defaultPageSize},pageToken={type="string",pattern="^[0-9]+$",description="nextPageToken from the previous page; keep filters unchanged."}}
	for _,name in {"listMessages","listThreads"} do
		local key=if name=="listMessages" then "messages" else "threads"
		add(name,object(searchProperties),{{folder="INBOX",from="sender@example.com",after="2026-11-01",maxResults=20}},nil,object({[key]=array(row),nextPageToken=text()},{key}))
	end
	for _,name in {"getMessage","getThread"} do
		local value=if name=="getThread" then "thread-1" else "message-1"
		local named=object(fields(bodyProperties,{id=ID}),{"id"})
		add(name,object({id=either(ID,named),opts=body},{"id"}),{{id={id=value,bodyFormat="text",maxBodyValueBytes=4096}} :: any,{id=value,opts={bodyFormat="auto",maxBodyValueBytes=0}}},{"id","opts"},if name=="getMessage" then envelope else object({id=ID,messages=array(envelope)},{"id","messages"}))
	end
	local list=array(id,1,batchSize)
	add("getMessages",object({input=either(list,object(fields(bodyProperties,{ids=list}),{"ids"})),opts=body},{"input"}),{{input={ids={"message-1" :: any,{id="message-2"}},bodyFormat="text",maxBodyValueBytes=4096}} :: any,{input={"message-1"},opts={bodyFormat="html"}}},{"input","opts"})
	for _,name in {"getProfile","listFolders","listIdentities","listAliases","listMailFolders"} do add(name,object({}),{empty},{}) end
	docs.getProfile.outputSchema=object({emailAddress=text(),accountId=ID,name=text(),capabilities=array(text()),canSend={type="boolean"}},{"emailAddress","accountId","name","capabilities","canSend"})
	docs.listFolders.outputSchema=object({folders=array({type="object",properties={id=ID,name=text(),role=either(text(),{type="null"}),parentId=either(ID,{type="null"}),totalEmails={type="integer",minimum=0},unreadEmails={type="integer",minimum=0}},required={"id","name"}})},{"folders"})
	docs.listIdentities.outputSchema=object({identities=array({type="object",properties={id=ID,email=text(),name=either(text(),{type="null"})},required={"id","email"}})},{"identities"})
	docs.listAliases.outputSchema=object({aliases=array({type="object",properties={email=text(),canSend={type="boolean"},masked={type="boolean"},identityId=ID,name=text(),maskedId=ID,state=text(),description=text(),forDomain=text()},required={"email","canSend","masked"}}),notes=array(text())},{"aliases","notes"})
	local attachmentInput=object({id=ID,attachments=array(attachment)},{"attachments"})
	attachmentInput.additionalProperties=true
	add("listAttachments",object({message=either(id,attachmentInput)},{"message"}),{{message="message-1"}},{"message"})
	local singleDownload=object({messageId=ID,attachmentId=ID,id=ID,path=path},{"messageId"})
	singleDownload.anyOf={{required={"attachmentId"}},{required={"id"}}}
	local downloads=object({messageId=ID,items=array(downloadItem)},{"messageId","items"})
	local downloadSchema=object({input=either(id,singleDownload),attachment=downloadItem,path=path},{"input"})
	downloadSchema.allOf={namedOrPositional({properties={input=singleDownload},["not"]={anyOf={{required={"attachment"}},{required={"path"}}}}},{required={"attachment"},properties={input=id}})}
	add("getAttachment",downloadSchema,{{input={messageId="message-1",attachmentId="blob-1",path="downloads/invoice.pdf"}} :: any,{input="message-1",attachment={id="blob-1",path="downloads/copy.pdf"}}},{"input","attachment","path"},download)
	local downloadsSchema=object({input=either(id,downloads),items=array(downloadItem)},{"input"})
	downloadsSchema.allOf={namedOrPositional({properties={input=downloads},["not"]={required={"items"}}},{required={"items"},properties={input=id}})}
	add("getAttachments",downloadsSchema,{{input={messageId="message-1",items={{id="blob-1",path="downloads/all.pdf"}}}} :: any,{input="message-1",items={"blob-1"}}},{"input","items"})
	for _,name in {"markRead","markUnread","deleteMessage","deleteMessages","destroyMessage","destroyMessages","archiveMessage","archiveMessages"} do
		add(name,object({ids=ids},{"ids"}),{{ids={"message-1" :: any,{id="message-2"}}} :: any,{ids="message-1"}},{"ids"},if string.match(name,"^mark") or string.match(name,"^destroy") then confirmed else moved)
	end
	add("trashMessage",object({id=id},{"id"}),{{id="message-1"}},{"id"},row)
	local move=object({ids=ids,id=ID,folder=ID},{"folder"});move.anyOf={{required={"ids"}},{required={"id"}}}
	local moveSchema=object({input=either(ids,move),folder=ID},{"input"})
	moveSchema.allOf={namedOrPositional({properties={input=move},["not"]={required={"folder"}}},{required={"folder"},properties={input=ids}})}
	for _,name in {"moveMessage","moveMessages"} do add(name,table.clone(moveSchema),{{input={ids={"message-1","message-2"},folder="INBOX"}} :: any,{input="message-1",folder="archive"}},{"input","folder"},moved) end
	local folder=object({name={type="string",minLength=1},parent=id,parentId=ID},{"name"})
	local folderSchema=object({input=either({type="string",minLength=1},folder),parent=id},{"input"})
	folderSchema.allOf={namedOrPositional({properties={input=folder},["not"]={required={"parent"}}},{properties={input={type="string",minLength=1}}})}
	add("createFolder",folderSchema,{{input={name="Receipts",parentId="INBOX"}} :: any,{input="Projects"}},{"input","parent"},object({id=ID,name=text()},{"id","name"}))
	local messageProperties={text=text("Plain-text message body; empty text is permitted."),subject=text(),identityId=ID,from={type="string",minLength=1,format="email"},cc=array(address),bcc=array(address),replyTo=array(address),attachments=array(upload)}
	local send=object(fields(messageProperties,{to=array(address,1)}),{"to","text"})
	add("sendMessage",send,{{to={{email="recipient@example.com",name="Recipient"}},subject="Receipt",text="Please find the receipt attached.",attachments={{path="receipt.pdf",filename="receipt.pdf",mimeType="application/pdf"}}}},nil,sent)
	local replyProperties=fields(messageProperties,{all={type="boolean",default=false}})
	local reply=object(fields(replyProperties,{id=ID,messageId=ID}),{"text"});reply.anyOf={{required={"id"}},{required={"messageId"}}}
	local replySchema=object({input=either(id,reply),options=object(replyProperties,{"text"})},{"input"})
	replySchema.allOf={namedOrPositional({properties={input=reply},["not"]={required={"options"}}},{required={"options"},properties={input=id}})}
	add("replyMessage",replySchema,{{input={id="message-1",text="Thank you!",all=true}} :: any,{input="message-1",options={text="Received.",cc={{email="colleague@example.com"}}}}},{"input","options"},sent)
	local configured={}
	for name in functions do if name~="help" then configured[name]=assert(docs[name],"missing schema " .. name) end end
	for name in docs do assert(descriptions[name],"orphan schema " .. name) end
	return configured
end
