package main

import (
	"fmt"
	"strings"
)

// Discovery describes these fields but omits the proto union and input-presence
// rules documented in the Docs and Slides REST "Requests" references.
// Keep the small semantic supplement separate from the generated field inventory.
var requiredFields = map[string]map[string]string{
	"gdrive": {"Permission": "type role"},
	"gdocs": {
		"AcceptSuggestionRequest": "suggestionId", "RejectSuggestionRequest": "suggestionId", "DeleteSuggestionRequest": "suggestionId",
		"AddCommentReplyRequest": "post", "DeleteCommentReplyRequest": "postId", "DeleteCommentRequest": "commentId",
		"CreateDropdownDefinitionRequest": "dropdownDefinition", "CreateHeaderRequest": "type", "CreateFooterRequest": "type",
		"CreateNamedRangeRequest": "name range", "CreateParagraphBulletsRequest": "range bulletPreset",
		"DeleteContentRangeRequest": "range", "DeleteParagraphBulletsRequest": "range",
		"DeleteDropdownDefinitionRequest": "dropdownDefinitionId", "DeleteFooterRequest": "footerId", "DeleteHeaderRequest": "headerId",
		"DeletePositionedObjectRequest": "objectId", "DeleteTabRequest": "tabId",
		"DeleteTableColumnRequest": "tableCellLocation", "DeleteTableRowRequest": "tableCellLocation",
		"InsertCommentRequest": "content range", "InsertDateRequest": "dateElementProperties", "InsertDropdownRequest": "dropdownDefinitionId",
		"InsertInlineImageRequest": "uri", "InsertPersonRequest": "personProperties", "InsertRichLinkRequest": "richLinkProperties",
		"InsertTableColumnRequest": "tableCellLocation", "InsertTableRowRequest": "tableCellLocation", "InsertTableRequest": "rows columns",
		"InsertTextRequest": "text", "Location": "index", "Range": "startIndex endIndex",
		"MergeTableCellsRequest": "tableRange", "UnmergeTableCellsRequest": "tableRange", "PinTableHeaderRowsRequest": "tableStartLocation",
		"ReplaceAllTextRequest": "containsText", "ReplaceImageRequest": "imageObjectId uri", "SubstringMatchCriteria": "text",
		"UpdateTextStyleRequest": "range fields", "UpdateParagraphStyleRequest": "range fields", "UpdateDocumentStyleRequest": "fields",
		"UpdateDocumentTabPropertiesRequest": "tabProperties fields", "UpdateSectionStyleRequest": "range fields",
		"UpdateTableColumnPropertiesRequest": "tableStartLocation fields", "UpdateTableRowStyleRequest": "tableStartLocation fields",
		"UpdateTableCellStyleRequest": "fields", "UpdateCommentPostRequest": "postId content",
		"UpdateDropdownDefinitionPropertiesRequest": "dropdownDefinitionId fields", "UpdateDropdownPropertiesRequest": "dropdownId fields",
		"UpdateNamedStyleRequest": "namedStyle fields",
	},
	"gslides": {
		"AddCommentReplyRequest": "commentId post", "DeleteCommentReplyRequest": "commentId postId", "DeleteCommentRequest": "commentId",
		"UpdateCommentPostRequest": "commentId postId content", "InsertCommentRequest": "content",
		"InsertTextRequest": "objectId text", "DeleteTextRequest": "objectId textRange",
		"DeleteObjectRequest": "objectId", "DuplicateObjectRequest": "objectId", "RefreshSheetsChartRequest": "objectId", "RerouteLineRequest": "objectId",
		"CreateImageRequest": "url elementProperties", "CreateShapeRequest": "shapeType elementProperties", "CreateTableRequest": "rows columns elementProperties",
		"CreateVideoRequest": "id source elementProperties", "CreateSheetsChartRequest": "spreadsheetId chartId elementProperties",
		"PageElementProperties": "pageObjectId", "CreateParagraphBulletsRequest": "objectId textRange bulletPreset", "DeleteParagraphBulletsRequest": "objectId textRange",
		"DeleteTableColumnRequest": "tableObjectId cellLocation", "DeleteTableRowRequest": "tableObjectId cellLocation",
		"InsertTableColumnsRequest": "tableObjectId cellLocation number", "InsertTableRowsRequest": "tableObjectId cellLocation number",
		"MergeTableCellsRequest": "objectId tableRange", "UnmergeTableCellsRequest": "objectId tableRange",
		"GroupObjectsRequest": "childrenObjectIds", "UngroupObjectsRequest": "objectIds", "UpdateSlidesPositionRequest": "slideObjectIds",
		"UpdatePageElementsZOrderRequest": "pageElementObjectIds operation", "UpdatePageElementTransformRequest": "objectId transform applyMode",
		"UpdatePageElementAltTextRequest": "objectId", "UpdateLineCategoryRequest": "objectId lineCategory",
		"ReplaceAllTextRequest": "containsText", "SubstringMatchCriteria": "text", "ReplaceImageRequest": "imageObjectId url",
		"ReplaceAllShapesWithImageRequest": "imageUrl", "ReplaceAllShapesWithSheetsChartRequest": "spreadsheetId chartId containsText",
		"UpdateImagePropertiesRequest": "objectId fields", "UpdateLinePropertiesRequest": "objectId fields", "UpdatePagePropertiesRequest": "objectId fields",
		"UpdateShapePropertiesRequest": "objectId fields", "UpdateSlidePropertiesRequest": "objectId fields", "UpdateVideoPropertiesRequest": "objectId fields",
		"UpdateTableBorderPropertiesRequest": "objectId fields", "UpdateTableCellPropertiesRequest": "objectId fields",
		"UpdateTableColumnPropertiesRequest": "objectId fields", "UpdateTableRowPropertiesRequest": "objectId fields",
		"UpdateTextStyleRequest": "objectId textRange fields", "UpdateParagraphStyleRequest": "objectId textRange fields", "Range": "type",
	},
	"gforms": {
		"CreateItemRequest": "item location", "DeleteItemRequest": "location", "MoveItemRequest": "originalLocation newLocation",
		"UpdateItemRequest": "item location updateMask", "UpdateFormInfoRequest": "updateMask", "UpdateSettingsRequest": "settings updateMask",
		"Location": "index", "SetPublishSettingsRequest": "publishSettings", "PublishSettings": "publishState", "PublishState": "isPublished isAcceptingResponses",
	},
	"gsheets": {
		"UpdateSpreadsheetPropertiesRequest": "fields", "UpdateSheetPropertiesRequest": "properties fields",
		"UpdateDimensionPropertiesRequest": "range fields", "UpdateCellsRequest": "fields", "RepeatCellRequest": "range fields",
		"DeleteSheetRequest": "sheetId", "DuplicateSheetRequest": "sourceSheetId", "UpdateNamedRangeRequest": "namedRange fields", "DeleteNamedRangeRequest": "namedRangeId",
		"AppendCellsRequest": "fields", "AppendDimensionRequest": "sheetId dimension length", "DeleteDimensionRequest": "range", "InsertDimensionRequest": "range",
		"MoveDimensionRequest": "source destinationIndex", "CopyPasteRequest": "source destination", "CutPasteRequest": "source destination",
		"MergeCellsRequest": "range mergeType", "UnmergeCellsRequest": "range", "SortRangeRequest": "range sortSpecs", "SetDataValidationRequest": "range",
		"FindReplaceRequest": "find", "UpdateBordersRequest": "range", "SetBasicFilterRequest": "filter", "ClearBasicFilterRequest": "sheetId",
		"AddConditionalFormatRuleRequest": "rule", "UpdateConditionalFormatRuleRequest": "index", "DeleteConditionalFormatRuleRequest": "index sheetId",
		"AddChartRequest": "chart", "UpdateChartSpecRequest": "chartId spec", "DeleteEmbeddedObjectRequest": "objectId",
		"AddTableRequest": "table", "UpdateTableRequest": "table fields", "DeleteTableRequest": "tableId",
	},
}

var unionFields = map[string]map[string]string{
	"gdocs": {
		"AddCommentReplyRequest": "commentId suggestionId", "DeleteCommentReplyRequest": "commentId suggestionId",
		"UpdateCommentPostRequest": "commentId suggestionId", "DeleteNamedRangeRequest": "name namedRangeId",
		"ReplaceNamedRangeContentRequest": "namedRangeId namedRangeName", "UpdateTableCellStyleRequest": "tableRange tableStartLocation",
	},
	"gslides": {"InsertCommentRequest": "objectId shapeTextAnchor tableAnchor tableCellTextAnchor"},
	"gsheets": {"UpdateCellsRequest": "start range", "AutoFillRequest": "range sourceAndDestination", "FindReplaceRequest": "range sheetId allSheets"},
}

func (c *converter) constraints(name string, schema object) error {
	properties := obj(schema["properties"])
	check := func(fields []string) error {
		for _, field := range fields {
			if properties[field] == nil {
				return fmt.Errorf("%s: documented constraint references missing field %s", name, field)
			}
		}
		return nil
	}
	if fields := strings.Fields(requiredFields[c.api][name]); len(fields) > 0 {
		if err := check(fields); err != nil {
			return err
		}
		schema["required"] = fields
		for _, field := range fields {
			if obj(properties[field])["type"] == "string" {
				obj(properties[field])["minLength"] = 1
			}
		}
	}
	union := unionFields[c.api][name]
	// Every Docs insertion with these two fields requires exactly one location.
	if c.api == "gdocs" && properties["location"] != nil && properties["endOfSegmentLocation"] != nil {
		union = "location endOfSegmentLocation"
	}
	if fields := strings.Fields(union); len(fields) > 0 {
		if err := check(fields); err != nil {
			return err
		}
		choices := []any{}
		for _, field := range fields {
			choices = append(choices, object{"required": []string{field}})
		}
		schema["oneOf"] = choices
	}
	if (c.api == "gdocs" || c.api == "gforms") && name == "WriteControl" {
		schema["not"] = object{"required": []string{"requiredRevisionId", "targetRevisionId"}}
	}
	if c.api == "gslides" && name == "Range" {
		schema["oneOf"] = []any{
			object{"properties": object{"type": object{"const": "ALL"}}},
			object{"properties": object{"type": object{"const": "FROM_START_INDEX"}}, "required": []string{"startIndex"}},
			object{"properties": object{"type": object{"const": "FIXED_RANGE"}}, "required": []string{"startIndex", "endIndex"}},
		}
	}
	if c.api == "gsheets" && name == "ValueRange" {
		obj(obj(properties["values"])["items"])["items"] = object{"type": []string{"string", "number", "boolean", "null"},
			"description": "Strings, numbers and booleans are cell values; null skips the cell, while an empty string clears it."}
	}
	if c.api == "gcalendar" && name == "EventDateTime" {
		// Calendar explicitly permits a local date-time when timeZone is set;
		// Discovery's RFC3339 format alone would reject that documented form.
		localTime := `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?$`
		dateTime := obj(properties["dateTime"])
		delete(dateTime, "format")
		dateTime["anyOf"] = []any{object{"format": "date-time"}, object{"pattern": localTime}}
		schema["if"] = object{"required": []string{"dateTime"}, "properties": object{"dateTime": object{"pattern": localTime}}}
		schema["then"] = object{"required": []string{"timeZone"}, "properties": object{"timeZone": object{"minLength": 1}}}
	}
	if c.api == "gdrive" && name == "Permission" {
		obj(properties["role"])["enum"] = []string{"owner", "organizer", "fileOrganizer", "writer", "commenter", "reader"}
		schema["oneOf"] = []any{
			object{"properties": object{"type": object{"enum": []string{"user", "group"}}}, "required": []string{"emailAddress"}},
			object{"properties": object{"type": object{"const": "domain"}}, "required": []string{"domain"}},
			object{"properties": object{"type": object{"const": "anyone"}}},
		}
	}
	if c.api == "gforms" && name == "CreateItemRequest" {
		// Item/Question are also used by partial updates. Enforce the creation
		// discriminators here, without requiring unchanged fields in updateItem.
		questionKinds := strings.Fields("choiceQuestion textQuestion scaleQuestion dateQuestion timeQuestion ratingQuestion rowQuestion")
		questionChoices := []any{}
		for _, kind := range questionKinds {
			branch := object{"required": []string{kind}}
			if kind == "choiceQuestion" {
				branch["properties"] = object{kind: object{"required": []string{"type", "options"}, "properties": object{"options": object{"minItems": 1}}}}
			}
			questionChoices = append(questionChoices, branch)
		}
		question := object{"oneOf": questionChoices, "not": object{"required": []string{"fileUploadQuestion"}}}
		item := object{"oneOf": []any{
			object{"required": []string{"questionItem"}, "properties": object{"questionItem": object{"required": []string{"question"}, "properties": object{"question": question}}}},
			object{"required": []string{"questionGroupItem"}, "properties": object{"questionGroupItem": object{"required": []string{"questions", "grid"}, "properties": object{"questions": object{"minItems": 1, "items": question}}}}},
			object{"required": []string{"pageBreakItem"}}, object{"required": []string{"textItem"}},
			object{"required": []string{"imageItem"}}, object{"required": []string{"videoItem"}},
		}}
		properties["item"] = object{"allOf": []any{properties["item"], item}}
	}
	return nil
}
