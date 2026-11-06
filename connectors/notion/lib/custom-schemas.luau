-- Native streaming helpers and the retained analytics route, whose schema is no
-- longer included in Notion's current Admin OpenAPI snapshot.
local nonempty: any = {type = "string", minLength = 1}
local id = {type = "string", minLength = 1, description = "Notion identifier; pass the ID returned by a prior operation."}
local saved = {type = "object", properties = {path = nonempty, url = nonempty, size = {type = "integer", minimum = 0}}, required = {"path", "url", "size"}, additionalProperties = false}
return {
	downloadFile = {inputSchema = {type = "object", properties = {
		url = {type = "string", pattern = "^https://", description = "Fresh signed file, plugin or export URL from Notion. Only the storage origins allowed by this connector may be downloaded; redirects are not followed."},
		path = {type = "string", minLength = 1, description = "Destination in the current session; replaced only after a successful transfer."},
	}, required = {"url", "path"}, additionalProperties = false, examples = {{url = "https://prod-files-secure.s3.us-west-2.amazonaws.com/workspace/guide.pdf?signature=fixture", path = "guide.pdf"}}}, outputSchema = saved,
		annotations = {readOnlyHint = false, destructiveHint = true, idempotentHint = true}},
	sendFileUpload = {inputSchema = {type = "object", properties = {file_upload_id = id,
		path = {type = "string", minLength = 1, description = "Existing session file, or prepared part file for a multipart upload."}, filename = {type = "string", minLength = 1, description = "Filename sent in multipart; defaults to the path basename."},
		content_type = {type = "string", minLength = 1, default = "application/octet-stream"}, part_number = {type = "integer", minimum = 1, maximum = 10000, description = "One-based part number for a multi_part upload."},
	}, required = {"file_upload_id", "path"}, additionalProperties = false, examples = {{file_upload_id = "b55c9c91-384d-452b-81db-d1ef79372b75", path = "upload.bin", filename = "notes.txt", content_type = "text/plain"}}},
		annotations = {readOnlyHint = false, destructiveHint = false, idempotentHint = false}},
	streamSession = {outputSchema = saved, annotations = {readOnlyHint = false, destructiveHint = true, idempotentHint = false}},
	adminListAnalyticsReports = {inputSchema = {type = "object", properties = {workspace_id = id, page_size = {type = {"integer", "null"}, minimum = 1, maximum = 100}, start_cursor = {type = {"string", "null"}, description = "Prior next_cursor. Null omits this parameter."}}, required = {"workspace_id"}, additionalProperties = false,
		examples = {{workspace_id = "b55c9c91-384d-452b-81db-d1ef79372b75", page_size = 10}}}, annotations = {readOnlyHint = true, idempotentHint = true}},
}
