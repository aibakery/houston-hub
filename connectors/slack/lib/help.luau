-- Native Slack options. The connector owns the allowed top-level keys; nested
-- Block Kit objects retain provider extensions. References: docs.slack.dev/reference/block-kit/.
type Object = {[string]: any}
local stringSchema, boolean = {type = "string"}, {type = "boolean"}
local nonempty = {type = "string", minLength = 1}
local function ref(name: string): any return {["$ref"] = "#/$defs/" .. name} end
local function array(item: any, max: number?): any return {type = "array", items = item, maxItems = max} end
local function object(properties: Object, required: {string}?): any
	return {type = "object", properties = properties, required = required, additionalProperties = true}
end
local function choice(values: {string}): any return {type = "string", enum = values} end
local function when(kind: string, schema: any): any
	return {["if"] = {properties = {type = {const = kind}}, required = {"type"}}, ["then"] = schema}
end
local defs: Object = {}
local richTypes = {"rich_text_section", "rich_text_list", "rich_text_quote", "rich_text_preformatted", "text", "link", "emoji", "user", "usergroup", "channel", "broadcast", "color", "date"}
defs.text = object({type = choice({"plain_text", "mrkdwn"}), text = {type = "string", minLength = 1, maxLength = 3000}, emoji = boolean, verbatim = boolean}, {"type", "text"})
defs.option = object({text = ref("text"), value = {type = "string", maxLength = 150}, description = ref("text"), url = stringSchema}, {"text", "value"})
defs.optionGroup = object({label = ref("text"), options = array(ref("option"), 100)}, {"label", "options"})
defs.confirm = object({title = ref("text"), text = ref("text"), confirm = ref("text"), deny = ref("text"), style = choice({"primary", "danger"})}, {"title", "text", "confirm", "deny"})
local otherTextTypes = table.clone(richTypes)
table.insert(otherTextTypes, "plain_text")
table.insert(otherTextTypes, "mrkdwn")
defs.element = object({type = {type = "string", minLength = 1, ["not"] = {enum = otherTextTypes}}, action_id = {type = "string", maxLength = 255}, text = ref("text"), value = stringSchema, url = stringSchema,
	style = choice({"primary", "danger"}), accessibility_label = stringSchema, placeholder = ref("text"), confirm = ref("confirm"),
	options = array(ref("option"), 100), option_groups = array(ref("optionGroup"), 100), initial_option = ref("option"), initial_options = array(ref("option")),
	initial_user = stringSchema, initial_users = array(stringSchema), initial_conversation = stringSchema, initial_conversations = array(stringSchema),
	initial_channel = stringSchema, initial_channels = array(stringSchema), initial_date = {type = "string", format = "date"}, initial_time = stringSchema,
	initial_value = stringSchema, focus_on_load = boolean, min_query_length = {type = "integer", minimum = 0}, max_selected_items = {type = "integer", minimum = 1},
	image_url = stringSchema, alt_text = stringSchema, slack_file = object({id = stringSchema, url = stringSchema}),
	filter = object({include = array(choice({"im", "mpim", "private", "public"})), exclude_external_shared_channels = boolean, exclude_bot_users = boolean}),
}, {"type"})
defs.element.allOf = {
	when("button", {required = {"text"}}),
	when("image", {required = {"alt_text"}, anyOf = {{required = {"image_url"}}, {required = {"slack_file"}}}}),
	when("static_select", {anyOf = {{required = {"options"}}, {required = {"option_groups"}}}}),
	when("checkboxes", {required = {"options"}}), when("radio_buttons", {required = {"options"}}),
}
-- Rich text is recursive: sections/lists contain inline text, links, mentions,
-- emoji or other rich-text nodes. Extra node types and attributes pass through.
defs.richText = object({type = choice(richTypes), text = stringSchema, elements = array(ref("richText")), url = stringSchema, user_id = stringSchema,
	channel_id = stringSchema, usergroup_id = stringSchema, name = stringSchema, unicode = stringSchema, range = stringSchema,
	style = {anyOf = {choice({"ordered", "bullet"}), object({bold = boolean, italic = boolean, strike = boolean, code = boolean})}},
	indent = {type = "integer", minimum = 0}, offset = {type = "integer", minimum = 0}, border = {type = "integer", minimum = 0},
	timestamp = {type = "integer"}, format = stringSchema, fallback = stringSchema, value = stringSchema,
}, {"type"})
defs.richText.allOf = {}
for kind, field in ({rich_text_section = "elements", rich_text_list = "elements", rich_text_quote = "elements", rich_text_preformatted = "elements",
	text = "text", link = "url", emoji = "name", user = "user_id", usergroup = "usergroup_id", channel = "channel_id", broadcast = "range", color = "value", date = "timestamp"} :: {[string]: string}) do
	table.insert(defs.richText.allOf, when(kind, {required = {field}}))
end
defs.block = object({type = nonempty, block_id = {type = "string", maxLength = 255}, text = {anyOf = {ref("text"), stringSchema}},
	fields = array(ref("text"), 10), accessory = ref("element"), elements = array({anyOf = {ref("element"), ref("text"), ref("richText")}}),
	image_url = stringSchema, alt_text = stringSchema, slack_file = object({id = stringSchema, url = stringSchema}), title = ref("text"),
	label = ref("text"), hint = ref("text"), element = ref("element"), optional = boolean, dispatch_action = boolean, expand = boolean,
	source = stringSchema, external_id = stringSchema, video_url = stringSchema, thumbnail_url = stringSchema, title_url = stringSchema,
	description = ref("text"), author_name = stringSchema, provider_name = stringSchema, provider_icon_url = stringSchema,
	rows = array(array({anyOf = {ref("richText"), object({type = {const = "raw_text"}, text = stringSchema}, {"type", "text"})}})),
	column_settings = array(object({align = choice({"left", "center", "right"}), is_wrapped = boolean})),
}, {"type"})
defs.block.allOf = {
	when("section", {anyOf = {{required = {"text"}}, {required = {"fields"}}}, properties = {text = ref("text")}}),
	when("header", {required = {"text"}, properties = {text = {allOf = {ref("text"), {properties = {type = {const = "plain_text"}, text = {maxLength = 150}}}}}}}),
	when("actions", {required = {"elements"}, properties = {elements = array(ref("element"), 25)}}),
	when("context", {required = {"elements"}, properties = {elements = array({anyOf = {ref("element"), ref("text")}}, 10)}}),
	when("image", {required = {"alt_text"}, anyOf = {{required = {"image_url"}}, {required = {"slack_file"}}}}),
	when("input", {required = {"label", "element"}}), when("file", {required = {"external_id", "source"}}),
	when("rich_text", {required = {"elements"}, properties = {elements = array(ref("richText"))}}),
	when("markdown", {required = {"text"}, properties = {text = {type = "string", maxLength = 12000}}}),
	when("table", {required = {"rows"}}),
	when("video", {required = {"alt_text", "title", "thumbnail_url", "video_url"}}),
}
defs.attachment = object({fallback = stringSchema, color = stringSchema, pretext = stringSchema, text = stringSchema,
	author_name = stringSchema, author_link = stringSchema, author_icon = stringSchema, title = stringSchema, title_link = stringSchema,
	image_url = stringSchema, thumb_url = stringSchema, footer = stringSchema, footer_icon = stringSchema, ts = {type = {"string", "integer"}},
	fields = array(object({title = stringSchema, value = stringSchema, short = boolean})), mrkdwn_in = array(stringSchema),
	blocks = array(ref("block"), 50), callback_id = stringSchema,
	actions = array(object({type = nonempty, name = stringSchema, text = stringSchema, value = stringSchema, url = stringSchema,
		style = stringSchema, options = array(object({text = stringSchema, value = stringSchema}))})),
})
local boolQuery = {enum = {true :: any, false, "true", "false", 0, 1, "0", "1"}}
local fields: Object = {
	cursor = nonempty, limit = {type = "integer", minimum = 1, maximum = 1000},
	types = {type = "string", pattern = "^(public_channel|private_channel|im|mpim)(,(public_channel|private_channel|im|mpim))*$", default = "public_channel,private_channel,im,mpim"},
	exclude_archived = {enum = boolQuery.enum, default = true}, oldest = nonempty, latest = nonempty, inclusive = boolQuery,
	include_all_metadata = boolQuery, include_locale = boolQuery, count = {type = "integer", minimum = 1, maximum = 100},
	page = {type = "integer", minimum = 1}, sort = {type = "string", enum = {"timestamp", "score"}, default = "timestamp"},
	sort_dir = {type = "string", enum = {"asc", "desc"}, default = "desc"}, highlight = boolQuery, query = stringSchema,
	thread_ts = nonempty, blocks = array(ref("block"), 50), attachments = array(ref("attachment"), 100),
	unfurl_links = boolean, unfurl_media = boolean, reply_broadcast = boolean, mrkdwn = boolean,
	parse = choice({"none", "full"}), link_names = {enum = {true :: any, false, 0, 1, "0", "1"}},
	metadata = object({event_type = nonempty, event_payload = {type = "object", additionalProperties = true}}, {"event_type", "event_payload"}),
	client_msg_id = {type = "string", format = "uuid"}, file_ids = {anyOf = {nonempty, array(nonempty)}},
	filename = nonempty, title = nonempty, alt_text = nonempty, channel = nonempty, text = nonempty,
}
return {definitions = defs, options = function(allowed: {[string]: boolean}, defaultLimit: number?): any
	local properties: Object = {}
	for name in allowed do
		assert(fields[name], "missing Slack option schema for " .. name)
		properties[name] = fields[name]
	end
	if defaultLimit and properties.limit then
		properties.limit = table.clone(properties.limit)
		properties.limit.default = defaultLimit
	end
	return {type = "object", properties = properties, additionalProperties = false}
end}
