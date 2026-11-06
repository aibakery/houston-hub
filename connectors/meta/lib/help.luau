local native=require("lib/native.luau").schemas
local examples=require("lib/examples.luau")
local function text(description: string?): any return {type="string",description=description} end
local function integer(minimum: number?,maximum: number?): any return {type="integer",minimum=minimum,maximum=maximum} end
local function enum(...: any): any return {enum={...}} end
local function object(properties: any,required: any?,closed: boolean?): any return {type="object",properties=properties,required=required or json.decode("[]"),additionalProperties=if closed then false else nil} end
local function array(items: any,minimum: number?,maximum: number?): any return {type="array",items=items,minItems=minimum,maxItems=maximum} end
local ID: any={type="string",minLength=1,pattern="^[A-Za-z0-9_][A-Za-z0-9_.:$=+\\-]*$",description="Meta ID string; numbers can lose precision."}
local HTTPS={type="string",pattern="^https://",format="uri",description="Public HTTPS URL that Meta can fetch."}
local boolean={type="boolean"}
local date: any={anyOf={integer(0),text("Unix timestamp or native date/time string.")}}
local function csv(items: any,minimum: number?,maximum: number?): any
	local token="[^,]+"
	if items.enum then token="(" .. table.concat(items.enum,"|") .. ")" end
	if items.pattern then token=string.sub(items.pattern,2,-2) end
	local repeated=if maximum then "{" .. ((minimum or 1)-1) .. "," .. (maximum-1) .. "}" else "*"
	return {anyOf={array(items,minimum or 1,maximum),{type="string",pattern="^" .. token .. "(," .. token .. ")" .. repeated .. "$"}},description="Nonempty array or comma-separated string."}
end
local function querySchema(schema: any): any
	if schema.type=="array" then return csv(schema.items or {}) end
	if schema.anyOf then
		local out=table.clone(schema);out.anyOf={}
		for _,branch in schema.anyOf do table.insert(out.anyOf,querySchema(branch)) end
		return out
	end
	return schema
end
-- SDK Object/map fields need the native nested shapes used by Messenger and
-- Instagram publishing. Keep extensions permitted for provider-added fields.
local button=object({type=enum("web_url","postback","phone_number","account_link","account_unlink","element_share","game_play"),title=text(),url=HTTPS,payload=text(),webview_height_ratio=enum("compact","tall","full")},{"type"})
local attachmentPayload=object({url=HTTPS,is_reusable=boolean,attachment_id=ID,template_type=enum("generic","button","media","receipt","airline_boardingpass","airline_checkin","airline_itinerary","airline_update"),text=text(),buttons=array(button),
	elements=array(object({title=text(),subtitle=text(),image_url=HTTPS,default_action=button,buttons=array(button),media_type=enum("image","video"),attachment_id=ID,url=HTTPS})),
})
local message=object({text=text("Messenger text; Instagram accepts at most 1,000 UTF-8 bytes."),attachment=object({type=enum("image","audio","video","file","template"),payload=attachmentPayload},{"type","payload"}),
	quick_replies=array(object({content_type=enum("text","user_phone_number","user_email"),title=text(),payload=text(),image_url=HTTPS},{"content_type"})),metadata=text(),
})
message.anyOf={{required={"text"}},{required={"attachment"}}}
local recipient=object({id=ID,comment_id=ID,user_ref=text(),phone_number=text(),name=object({first_name=text(),last_name=text()})})
recipient.oneOf={{required={"id"}},{required={"comment_id"}},{required={"user_ref"}},{required={"phone_number"}}}
native.sendMessage.properties.recipient=recipient
native.sendMessage.properties.message=message
native.sendMessage.properties.tag=text("Meta-approved message tag, for example HUMAN_AGENT when authorized.")
native.sendMessage.properties.reply_to=object({mid=ID},{"mid"})
native.sendMessage.properties.sender_action=enum("mark_seen","typing_on","typing_off","react","unreact","MARK_SEEN","TYPING_ON","TYPING_OFF","REACT","UNREACT")
native.sendMessage.anyOf={{required={"message"}},{required={"sender_action"}}}
native.sendInstagramPrivateReply=object({recipient=object({comment_id=ID},{"comment_id"}),message=object({text=text("One private reply per Instagram comment, at most 1,000 UTF-8 bytes.")},{"text"})})
native.createPost.properties.attached_media=array(object({media_fbid=ID},{"media_fbid"}),1)
native.createPost.properties.place={anyOf={ID,object({id=ID})}}
native.createPost.properties.child_attachments=array(object({link=HTTPS,name=text(),description=text(),picture=HTTPS}))
native.createPost.anyOf={{required={"message"}},{required={"link"}},{required={"attached_media"}}}
native.createComment.anyOf={{required={"message"}},{required={"attachment_url"}},{required={"attachment_id"}},{required={"attachment_share_url"}}}
local container=native.createInstagramContainer
container.properties.media_type=enum("REELS","STORIES","CAROUSEL","VIDEO")
container.properties.caption={type="string",maxLength=2200}
container.properties.children=csv(ID,2,10)
container.properties.user_tags=array(object({username=text(),x={type="number",minimum=0,maximum=1},y={type="number",minimum=0,maximum=1}},{"username"}))
container.properties.product_tags=array(object({product_id=ID,x={type="number",minimum=0,maximum=1},y={type="number",minimum=0,maximum=1}},{"product_id"}))
container.properties.trial_params=object({graduation_strategy=text("Native trial-reel graduation strategy.")})
for _,field in {"image_url","video_url","cover_url"} do container.properties[field]=HTTPS end
container.anyOf={{required={"image_url"}},{required={"video_url"}},{required={"children"}}}
container.allOf={
	{["if"]={properties={media_type={const="CAROUSEL"}},required={"media_type"}},["then"]={required={"children"}}} :: any,
	{["if"]={properties={media_type={enum={"VIDEO","REELS"}}},required={"media_type"}},["then"]={required={"video_url"}}},
}
native.publishInstagramMedia.properties.creation_id=ID
for name,urlField in {uploadPhoto="url",uploadVideo="file_url"} do
	local schema=native[name]
	schema.properties.source=false
	schema.properties.path={type="string",minLength=1,pattern="^[^\\u0000-\\u001f\\u007f]+$",description="Existing session file, streamed as multipart source. Cannot be combined with a URL."}
	schema.properties[urlField]=HTTPS
	schema.oneOf={{required={"path"},["not"]={required={urlField}}} :: any,{required={urlField},["not"]={required={"path"}}}}
	schema.allOf={{["if"]={required={"path"}},["then"]={additionalProperties={["not"]={type="null"}},["not"]={anyOf={{required={"source"}},{required={"url"}},{required={"file_url"}}}}}}}
end
local fallback={since=date,["until"]=date,include_hidden=boolean,show_expired=boolean,summary={anyOf={boolean,text("Native summary selector, for example total_count.")}},
	limit=integer(1,100),after=text("paging.cursors.after."),before=text("paging.cursors.before."),
	user_id=ID,q={type="string",minLength=1},metric=csv(text()),period=text(),date_preset=text(),breakdown=csv(text()),metric_type=text(),timeframe=text(),
	folder=text(),platform=enum("messenger","instagram"),type=text(),filter=enum("toplevel","stream"),order=enum("chronological","reverse_chronological"),
}
-- Page insights declares list<Object> in the SDK, but Graph accepts metric and
-- breakdown names as CSV strings. Names depend on the Page/Instagram node kind.
native.getInsights.properties.metric=array({type="string",pattern="^[a-z][a-z0-9_]*$"},1)
native.getInsights.properties.breakdown=array({type="string",pattern="^[a-z][a-z0-9_]*$"},1)
native.listConversations.properties.platform=enum("messenger","instagram","MESSENGER","INSTAGRAM")
local graphFields={type="string",minLength=1,maxLength=4096,pattern="^[A-Za-z0-9_,.(){}:=+/ -]+$",["not"]={pattern="[tT][oO][kK][eE][nN]"},description="Native Graph field list with expansions; token fields are forbidden."}
return function(endpoints: any,reserved: any): any
	local docs={}
	for name,endpoint in endpoints do
		local write=endpoint.method=="POST"
		local source=native[name]
		if write then assert(source,"missing native schema " .. name) end
		local schema: any=if write then table.clone(source) else object({})
		local properties,required={},json.decode("[]")
		if write then
			for field,s in source.properties do if endpoint.body==nil or table.find(endpoint.body,field) then properties[field]=s end end
			local blocked={};for field in reserved do table.insert(blocked,field);properties[field]=false end;table.sort(blocked)
			schema.propertyNames={pattern="^[a-z][a-z0-9_]*$",["not"]={enum=blocked}}
		end
		for field in string.gmatch(endpoint.path,"{([%w_]+)}") do
			properties[field]=if field=="post" then {type="string",pattern="^[0-9]+_[0-9]+$"} else ID
			table.insert(required,field)
		end
		if endpoint.method=="GET" then properties.fields=table.clone(graphFields);properties.fields.default=endpoint.fields end
		for _,group in {endpoint.query or {},endpoint.paging or {}} do
			for _,field in group do
				local s=if source then source.properties[field] else nil
				if field=="since" or field=="until" or field=="summary" or field=="limit" or field=="after" or field=="before" then s=fallback[field] end
				if not s then s=fallback[field] end
				assert(s,"missing query schema " .. name .. "." .. field)
				s=querySchema(s)
				if field=="limit" and (name=="listInstagramComments" or name=="listHashtagTopMedia" or name=="listHashtagRecentMedia") then s=integer(1,50) end
				properties[field]=s
			end
		end
		for _,field in endpoint.required or {} do assert(properties[field],"missing required field " .. name .. "." .. field);table.insert(required,field) end
		schema.type="object";schema.properties=properties;schema.required=required
		if not write or endpoint.body then schema.additionalProperties=false end
		if endpoint.paging then
			properties.next={type="string",minLength=1,description="Opaque paging.next from this same operation. Pass next alone; do not send a URL or other options."}
			schema.required=nil
			schema.oneOf={{required=required,["not"]={required={"next"}}} :: any,{required={"next"},propertyNames={const="next"}}}
		end
		assert(examples[name] and #examples[name]>0,"missing example " .. name);schema.examples=examples[name]
		docs[name]={description=endpoint.about .. (if endpoint.fields then " Default fields: " .. endpoint.fields .. "." else "") .. " " .. endpoint.method .. " " .. endpoint.path,
			inputSchema=schema,outputSchema={type="object"},annotations={readOnlyHint=endpoint.method=="GET"}}
	end
	for name in examples do assert(endpoints[name],"example without operation " .. name) end
	return docs
end
