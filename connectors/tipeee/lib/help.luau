-- Native creator fields from the Tipeee website contract described in connector.luau,
-- cross-checked with https://en.tipeee.com/_nuxt/20261029144418.30.js.
-- Source SHA-256: 1da50dd8c34ff9b3484579383c98b711ef41d8aeb0c286c0f2c0b7df0a717f14
-- Tipeee has no complete public creator-management OpenAPI specification.
local function text(description: string?, maximum: number?): any
	return {type="string", description=description, maxLength=maximum}
end
local function number(minimum: number?, maximum: number?): any return {type="number", minimum=minimum, maximum=maximum} end
local function integer(minimum: number?, maximum: number?): any return {type="integer", minimum=minimum, maximum=maximum} end
local function enum(...: any): any return {enum={...}} end
local function object(properties: any, required: any?, closed: boolean?): any
	return {type="object",properties=properties,required=required,additionalProperties=if closed then false else nil}
end
local function array(items: any, maximum: number?): any return {type="array",items=items,maxItems=maximum} end
local function nullable(schema: any): any return {anyOf={schema,{type="null"}}} end
-- Multipart nulls omit a field. Required native fields still need a value.
local function formSchema(schema: any): any
	if type(schema)~="table" then return schema end
	local out=table.clone(schema)
	if schema.properties then
		out.properties={}
		for name,child in schema.properties do
			local value=formSchema(child)
			out.properties[name]=if child==false or table.find(schema.required or {},name) then value else nullable(value)
		end
	end
	if schema.items then out.items=formSchema(schema.items) end
	if type(schema.additionalProperties)=="table" then out.additionalProperties=formSchema(schema.additionalProperties) end
	return out
end
local boolean = {type="boolean"}
local identifier: any = {anyOf={integer(0,9007199254740991),{type="string",minLength=1,pattern="^[A-Za-z0-9_-]+$"}}}
local function translations(properties: any, required: any?): any
	return {type="object",minProperties=1,propertyNames={pattern="^[A-Za-z0-9_-]+$"},additionalProperties=object(properties,required)}
end
local richText = translations({html=text("Native HTML."),components={description="Native editor component data; preserve when editing."}})
local project = object({translations=translations({name=text("Project name.")},{"name"}),slug=identifier,lang=text("Native language code, for example en or fr."),categories=array(integer(1)),tags=array(object({name=text()}))})
local crop = object({x=number(),y=number(),width=number(0),height=number(0),delete=boolean})
local media = object({uploadedFileOptions=crop,delete=boolean})
local stock = object({unlimited=boolean,quantity=integer(0)})
local reward = object({price=number(1,5000),translations=translations({name=text(nil,100),description_v2=text("Native HTML reward description.",1500)},{"name"}),presale=boolean,has_presale=boolean,transition=text("Native reward lifecycle transition."),modules=object({
	display=object({is_pinned=boolean,is_private=boolean,private_link=text(),start=text("ISO date/time."),["end"]=text("ISO date/time."),_is_Activate=boolean}),
	stock=object({noReset=boolean,available=stock,perUser=stock,_is_Activate=boolean}),
	attachment=object({content=text(),files=array({description="Native uploaded file record; preserve fields from getReward."},3),links=array(object({name=text(),url=text()}),3),_is_Activate=boolean}),
	discord=object({role_name=text(),role_id=identifier,duration=number(0),_is_Activate=boolean}),
	shipping=object({addressRequired=boolean,phonenumberRequired=boolean,_is_Activate=boolean}),
	custom=object({settings=array(object({name=text(),options=array(object({name=text(),is_additional_config=boolean},{"name"}))},{"name","options"}))}),
})})
local news = object({name=text(),contentv2=object({translations=richText}),draft=boolean,private=boolean,
	parameters=object({private_type=enum("amount","rewards"),private_rule_amount=number(0),private_rule_rewards=array(identifier),tip_content=enum(0,1)}),
	tags=array(object({name=text()},{"name"})),isPinned=boolean,publishedAt=text("Native publication date/time."),
	survey=object({name=text(),questions=array(object({type=text("Native question type."),name=text(),answers=array(object({name=text()},{"name"}))},{"type","name"}))}),
})
local goal = object({translations=translations({name=text(),description=text("Native HTML.",1024)},{"name"}),amount=number(0)})
local flag = object({value=enum(0,1)},{"value"})
local widget = {theme=text(),text_color_var=text("CSS color value.")}
local function widgetFields(fields: any): any local p=table.clone(widget); for k,v in fields do p[k]=v end; return object(p) end
local bodies = {
	createProject=project,createOneOffProject=project,updateProject=project,
	updateProjectDescription=object({translations=richText}),
	updateCampaign=object({campaignType=enum("per_month","per_content","per_project"),campaignName=text(),perProjectCampaign=object({campaignGoalType=enum("amount","presale"),campaignGoal=number(0),campaignDeadlineType=text(),campaignDeadlineDays=integer(1),campaignDeadline=text("Native deadline date.")})}),
	updateProjectLinks=object({links=array(object({code=text(),value=text()},{"code","value"}),12)}),
	updateProjectAvatar=object({avatar=media}),updateProjectCover=object({cover=media}),
	updateProjectSettings=object({parameters=object({hidedAmount=flag,recurring_only=flag,notification_tip=flag,deleted_sub_notification=flag,nsfw=flag}),thanksMail=object({content=text(nil,1000)})}),
	prepareProjectPublication=object({},nil,true),
	publishProject=object({tipeee={const="on"},adyen={const="on"},hyperwallet={const="on"}},nil,true),
	closeProject=object({token={type="string",pattern="^[0-9]{6}$",description="One-time emailed closure code, not the session token."}},nil,true),
	createGoal=goal,updateGoal=goal,createReward=reward,updateReward=reward,
	transitionReward=object({transition=enum("archive","delete")}),cloneReward=object({},nil,true),
	createNews=news,updateNews=news,
	createComment=object({body={type="string",minLength=1,maxLength=1024},parent=identifier}),
	blockTipper=object({target=identifier,status={const="TIP_BANNED"}}),
	findOrCreateThread=object({project=integer(1),receiver=identifier}),
	sendMessage=object({action=enum("CREATE","RESPONSE","ERRATUM"),content=text(),title=text(),project=integer(1),thread=identifier,parent=identifier,
		rules=object({campaign=identifier,rewards=array(identifier)},nil,false),attachments=array(text("Uploaded attachment slug."),6)}),
	renameThread=object({title=text()}),sendSupportMessage=object({content={type="string",minLength=1,maxLength=3000}}),
	uploadMessageFileChunk=object({fileId=identifier,chunkIndex=integer(0),totalChunks=integer(1),fileName={type="string",minLength=1}}),
	uploadMedia=object({}),
	configureAlertsWidget=widgetFields({animation=text(),show_message=boolean,sound=object({type=text(),static_id=identifier,volume=number(0,1)})}),
	configureGoalsWidget=widgetFields({name=text(),initial_amount=number(0),goal_amount=number(0),reset=boolean,reset_at=text("Native reset date/time.")}),
	configureLastsWidget=widgetFields({events_count=integer(1),show_amount=boolean,show_title=boolean}),
	configureTotalsWidget=widgetFields({show_amount=boolean,show_project_avatar=boolean}),
}
bodies.sendMessage.allOf = {
	{["if"]={properties={action={const="CREATE"}},required={"action"}},["then"]={required={"project","title","rules"}}},
	{["if"]={properties={action={const="RESPONSE"}},required={"action"}},["then"]={required={"thread"}}},
	{["if"]={properties={action={const="ERRATUM"}},required={"action"}},["then"]={required={"parent","thread"}}},
}
local query = {
	page=integer(1),perPage=integer(1),slug=identifier,read=enum("true","false"),type=text(),token=text("Native pagination cursor."),direction=enum("next","previous"),
	q=text(),mode=text(),lang=text("Native language code."),category=identifier,campaign_type=enum("per_month","per_content","per_project"),
	status=text(),stock=text(),endDate=text("Native date filter."),priceMin=number(0),priceMax=number(0),rewardSort=text("Native reward sort value."),
	latest=boolean,statusFilter=text("For example draft."),rewardId=identifier,noReward=enum(0,1),year={type="string",pattern="^[0-9]{4}$"},
	timeUnit=text("Native time unit, for example DAY."),startDate=text("YYYY-MM-DD."),inbox_type=text("Native inbox type."),project=integer(1),
	isPrivate=boolean,width=integer(1),height=integer(1),date=text("Native date filter."),
}
local file = object({path={type="string",minLength=1},filename={type="string",minLength=1},contentType=text()}, {"path","filename","contentType"},true)
local formScalar: any = {type={"string","number","boolean","null"}}
local formValue: any = {anyOf={formScalar,array({["$ref"]="#/$defs/FormValue"}),{type="object",propertyNames={pattern="^[A-Za-z0-9_-]+$"},additionalProperties={["$ref"]="#/$defs/FormValue"}}}}
local examples = require("lib/examples.luau")
return function(endpoints: any): any
	local docs = {}
	for name, endpoint in endpoints do
		local properties, required = {}, json.decode("[]")
		for field in string.gmatch(endpoint.path,"{([%w_]+)}") do
			local s: any = identifier
			if field == "document" then s={type="string",pattern="^[A-Za-z0-9_-]+\\.pdf$"}
			elseif field == "report" then s={type="string",pattern=if name=="downloadPayments" then "^[A-Za-z0-9_-]+_[0-9]{4}\\.(csv|xlsx)$" else "^[A-Za-z0-9_-]+\\.(csv|xlsx)$"} end
			properties[field]=s; table.insert(required,field)
		end
		for _,field in endpoint.query or {} do
			assert(query[field], "missing query schema " .. name .. "." .. field)
			local s = query[field]
			if name=="listTopTippers" and field=="perPage" then s=integer(2,150)
			elseif name=="listProjectFeed" and field=="type" then s=enum("ALL","NEWTIP","COMMENT","CANCELED","VERIFICATION","OTHER")
			elseif name=="uploadMedia" and field=="type" then s=enum("image","audio","document","pdf")
			elseif field=="year" then s={anyOf={s,integer(1000,9999)}} end
			if table.find(endpoint.required or {},field) then properties[field]=s;table.insert(required,field) else properties[field]=nullable(s) end
		end
		local schema=object(properties,required,true)
		if endpoint.body=="form" or endpoint.body=="json" then
			assert(bodies[name],"missing native body schema " .. name)
			local data=table.clone(bodies[name]);data.properties=table.clone(data.properties)
			data.properties._method=false;data.properties.access_token=false
			data.required=endpoint.required
			properties.data=data
			if endpoint.required and #endpoint.required>0 then table.insert(required,"data") end
			if endpoint.body=="form" then
				data=formSchema(data);properties.data=data
				schema["$defs"]={FormValue=formValue}
				data.allOf=table.clone(data.allOf or {});table.insert(data.allOf,{["$ref"]="#/$defs/FormValue"})
				properties.files={type="object",propertyNames={pattern="^[A-Za-z0-9_-]+[A-Za-z0-9_\\[\\]-]*$",["not"]={enum={"_method","access_token"}}},additionalProperties=file}
				if name=="uploadMedia" or name=="uploadMessageFileChunk" then
					table.insert(required,"files");properties.files.required={if name=="uploadMedia" then "uploadedFile" else "file"}
				end
			end
		elseif endpoint.body=="download" then properties.output={type="string",minLength=1};table.insert(required,"output") end
		assert(examples[name] and #examples[name]>0,"missing example " .. name)
		schema.examples=examples[name]
		local record={description=endpoint.about .. " " .. endpoint.method .. " " .. endpoint.path,inputSchema=schema,
			annotations={readOnlyHint=not (endpoint.write==true or endpoint.method~="GET")}}
		if endpoint.body=="download" then record.outputSchema=object({path=text(),size=integer(0),url=text()}, {"path","size","url"}) end
		docs[name]=record
	end
	for name in examples do assert(endpoints[name],"example without endpoint " .. name) end
	return docs
end
