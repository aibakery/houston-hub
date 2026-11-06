-- Native writes follow Dolibarr 24.0.2 API controllers, with older stock aliases.
-- https://github.com/Dolibarr/dolibarr/tree/24.0.2/htdocs
-- Custom modules can add fields; the installed API explorer remains authoritative.
local MAX_ID=9007199254740991
local function integer(minimum: number?,maximum: number?): any return {type="integer",minimum=minimum,maximum=maximum} end
local function text(description: string?): any return {type="string",description=description} end
local function array(items: any,minimum: number?): any return {type="array",items=items,minItems=minimum} end
local function object(properties: any,required: any?,closed: boolean?): any return {type="object",properties=properties,required=required or json.decode("[]"),additionalProperties=if closed then false else nil} end
local function enum(...: any): any return {enum={...}} end
local digits="9007199254740991"
local alternatives={digits,"[1-9][0-9]{0,14}"}
for index=1,#digits do
	local digit=tonumber(string.sub(digits,index,index)) :: number
	local first=if index==1 then 1 else 0
	if digit>first then table.insert(alternatives,string.sub(digits,1,index-1) .. "[" .. first .. "-" .. (digit-1) .. "][0-9]{" .. (#digits-index) .. "}") end
end
local ID: any={anyOf={integer(1,MAX_ID),{type="string",pattern="^(" .. table.concat(alternatives,"|") .. ")$"}}}
local DECIMAL: any={anyOf={{type="number"} :: any,{type="string",pattern="^[+-]?[0-9]+(\\.[0-9]+)?$"}},description="Native decimal amount or quantity, as a number or decimal string."}
local DATE: any={anyOf={integer(0,MAX_ID),{type="string",pattern="^[0-9]+$"}},description="Unix timestamp in seconds."}
local flag=enum(0,1,"0","1")
local extra={type="object",propertyNames={pattern="^options_[A-Za-z0-9_]+$"},additionalProperties=true,description="Custom field values keyed by options_<code>; the installed module defines each value's type."}
local function fields(groups: any,additional: any?): any
	local p={}
	for _,group in groups do for name in string.gmatch(group[1],"%S+") do p[name]=group[2] end end
	for name,value in additional or {} do p[name]=value end
	return object(p)
end
local common={array_options=extra,ref_ext=text("External reference used for reconciliation."),note_public=text(),note_private=text()}
local thirdparty=fields({
	{"name name_alias address zip town phone phone_mobile fax email url code_client code_fournisseur code_compta code_compta_fournisseur supplier_account tva_intra default_lang siren siret ape idprof1 idprof2 idprof3 idprof4 idprof5 idprof6",text()},
	{"country_id state_id typent_id effectif_id forme_juridique_code parent cond_reglement_id mode_reglement_id price_level",integer(0)},
	{"client",enum(0,1,2,3)}, {"fournisseur tva_assuj localtax1_assuj localtax2_assuj",flag},
	{"capital outstanding_limit customer_rate supplier_rate",DECIMAL},
},{socialnetworks={type="object",additionalProperties={type="string"}}})
local contact=fields({
	{"lastname firstname civility_id address zip town phone_pro phone_perso phone_mobile fax email poste",text()},
	{"socid country_id state_id",integer(0)}, {"statut",flag}, {"birthday",DATE},
})
local product=fields({
	{"ref label description description_short note barcode url country_code customcode accountancy_code_sell accountancy_code_buy accountancy_code_sell_intra accountancy_code_sell_export accountancy_code_buy_intra accountancy_code_buy_export",text()},
	{"price price_ttc price_min price_min_ttc tva_tx localtax1_tx localtax2_tx pmp cost_price weight length width height surface volume stock_alert seuil_stock_alerte desiredstock",DECIMAL},
	{"type",enum(0,1)}, {"status status_buy tosell tobuy finished",flag},
	{"weight_units length_units width_units height_units surface_units volume_units fk_unit barcode_type country_id",integer()},
	{"price_base_type",enum("HT","TTC")},
},{multiprices={type="object",additionalProperties=DECIMAL}})
local line=fields({
	{"desc label ref_ext origin",text()},
	{"subprice qty tva_tx localtax1_tx localtax2_tx remise_percent pa_ht multicurrency_subprice situation_percent",DECIMAL},
	{"fk_product fk_remise_except fk_parent_line fk_fournprice fk_unit origin_id fk_prev_id fk_code_ventilation",integer(0)},
	{"info_bits product_type rang special_code",integer()}, {"date_start date_end",DATE}, {"price_base_type",enum("HT","TTC")},
},{array_options=extra})
local document=fields({
	{"socid",ID}, {"date date_livraison date_lim_reglement",DATE},
	{"cond_reglement_id mode_reglement_id fk_account fk_project warehouse_id shipping_method_id fk_delivery_address availability_id demand_reason_id",integer(0)},
	{"type fk_facture_source",integer(0)}, {"multicurrency_code model_pdf",text()}, {"multicurrency_tx remise_percent",DECIMAL},
},{lines=array(line),linked_objects={type="object",additionalProperties=array(ID)},contacts_ids={type="object",additionalProperties=array(ID)}})
for _,schema in {thirdparty,contact,product,document} do for name,value in common do schema.properties[name]=value end end
local stock=fields({
	{"product_id warehouse_id",ID}, {"qty price",DECIMAL}, {"type",enum(0,1,2,3)},
	{"batch lot movementcode label movementlabel origin_type",text()}, {"origin_id",integer(0)},
	{"datem sellBy eatBy dlc dluo",({anyOf={DATE,text("Native stock date (YYYY-MM-DD or Unix timestamp); names vary by Dolibarr version.")}} :: any)},
})
local validate=fields({{"idwarehouse notrigger",integer(0)}})
local invoiceValidate=fields({{"force_number",text("Explicit invoice number; normally omit to use automatic numbering.")},{"idwarehouse notrigger",integer(0)}})
local payment=fields({{"datepaye",DATE},{"paymentid accountid",ID},{"closepaidinvoices",enum("yes","no")},{"num_payment comment chqemetteur chqbank",text()} })
local bodies={createThirdparty=thirdparty,updateThirdparty=thirdparty,createContact=contact,updateContact=contact,createProduct=product,updateProduct=product,
	createStockMovement=stock,createOrder=document,addOrderLine=line,validateOrder=validate,closeOrder=fields({{"notrigger",integer(0)}}),
	createInvoice=document,addInvoiceLine=line,validateInvoice=invoiceValidate,addInvoicePayment=payment}
local examples=require("lib/examples.luau")
return function(endpoint: any,options: {string},secret: any): any
	local properties,required,args={},json.decode("[]"),json.decode("[]")
	if string.find(endpoint.path,"{id}",1,true) then properties.id=ID;table.insert(required,"id");table.insert(args,"id") end
	if endpoint.fields then
		assert(bodies[endpoint.name],"missing native fields " .. endpoint.name)
		local body=table.clone(bodies[endpoint.name]);body.properties=table.clone(body.properties);body.properties.id=false
		body.required=endpoint.required or json.decode("[]")
		body.minProperties=if endpoint.fields=="required" then 1 else 0
		properties.fields=body;table.insert(args,"fields")
		if endpoint.fields=="required" then table.insert(required,"fields") end
	elseif #options>0 then
		local excluded={}
		for name in secret do table.insert(excluded,name) end
		table.sort(excluded)
		local function insensitive(value: string): string return (string.gsub(value,"%a",function(c) return "[" .. string.lower(c) .. string.upper(c) .. "]" end)) end
		local names,filters={},{}
		for _,name in excluded do
			table.insert(names,insensitive(name))
			local chars={};for index=1,#name do table.insert(chars,insensitive(string.sub(name,index,index))) end
			table.insert(filters,table.concat(chars,"[^A-Za-z0-9_.:()]*"))
		end
		local sql={type="string",minLength=1,maxLength=4000,pattern="\\S",["not"]={pattern="\\((?:[^:()]*\\.)?[^A-Za-z0-9_.:()]*(?:" .. table.concat(filters,"|") .. ")[^A-Za-z0-9_.:()]*:"},description="Native Dolibarr sqlfilters; column names depend on the endpoint. Withheld credential columns cannot be queried."}
		local queries={sortfield={type="string",pattern="^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)?$",["not"]={pattern="(^|\\.)(" .. table.concat(names,"|") .. ")$"}},
			sortorder=enum("ASC","DESC"),limit=integer(1,200),page=integer(0,MAX_ID),sqlfilters=sql,sqlfilterlines=sql,
			properties=array({type="string",maxLength=4000,pattern="^[A-Za-z_][A-Za-z0-9_]*$"},1),
			thirdparty_ids={anyOf={ID,array(ID,1)}},category=ID,selected_warehouse_id=ID,type={type="string",maxLength=4000,pattern="^[A-Za-z_][A-Za-z0-9_]*$"},includestockdata={type="boolean"},
			mode=integer(),status=text()}
		local selected={}
		for _,name in options do assert(queries[name],"missing option " .. name); selected[name]=queries[name] end
		for name,choices in endpoint.choices or {} do selected[name]={enum=choices} end
		properties.opts=object(selected,endpoint.required,true);table.insert(args,"opts")
		if endpoint.required then table.insert(required,"opts") end
	end
	local schema=object(properties,required,true)
	assert(examples[endpoint.name],"missing examples " .. endpoint.name);schema.examples=examples[endpoint.name]
	return {description=(endpoint.method or "GET") .. " " .. endpoint.path .. ". Returns " .. (endpoint.returns or (if endpoint.list then "an array of native records" else "the native record")) .. ". Custom module fields and version-dependent fields are described by the installed API explorer.",
		args=args,inputSchema=schema,annotations={readOnlyHint=endpoint.method==nil or endpoint.method=="GET"}}
end
