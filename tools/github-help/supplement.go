package main

func supplement(name string, s object) {
	switch name {
	case "setLabels":
		// The reference explicitly permits clearing all labels, although its
		// generated array alternatives say minItems=1. Keep the native element
		// shapes and use anyOf so the empty arrays may match both alternatives.
		body := obj(list(s["allOf"])[0])
		arrays := []any{}
		for _, branch := range list(body["oneOf"]) {
			if labels := obj(obj(obj(branch)["properties"])["labels"]); labels != nil {
				labels["minItems"] = 0
				arrays = append(arrays, labels)
			}
		}
		if len(arrays) != 2 {
			panic("review native setLabels alternatives")
		}
		s["allOf"] = []any{object{"type": "object", "properties": object{"labels": object{"anyOf": arrays}}}}
	case "createPull":
		s["anyOf"] = []any{object{"required": []string{"title"}}, object{"required": []string{"issue"}}}
	case "requestReviewers":
		s["anyOf"] = []any{object{"required": []string{"reviewers"}, "properties": object{"reviewers": object{"minItems": 1}}}, object{"required": []string{"team_reviewers"}, "properties": object{"team_reviewers": object{"minItems": 1}}}}
	case "updateGist":
		s["anyOf"] = []any{object{"required": []string{"description"}}, object{"required": []string{"files"}}}
	case "createTree":
		obj(s["properties"])["tree"] = object{"type": "array", "items": object{"oneOf": []any{object{"required": []string{"sha"}}, object{"required": []string{"content"}}}}}
	case "createPullReviewComment":
		s["anyOf"] = []any{object{"required": []string{"line"}}, object{"required": []string{"position"}}, object{"required": []string{"in_reply_to"}}, object{"required": []string{"subject_type"}, "properties": object{"subject_type": object{"const": "file"}}}}
		for _, field := range []string{"line", "start_line", "position"} {
			obj(s["properties"])[field] = object{"type": "integer", "minimum": 1}
		}
		obj(s["properties"])["start_side"] = object{"enum": []string{"LEFT", "RIGHT"}}
		s["allOf"] = append(list(s["allOf"]), object{"if": object{"required": []string{"start_line"}, "not": object{"required": []string{"in_reply_to"}}}, "then": object{"required": []string{"line", "start_side"}}})
	case "createPullReview", "submitPullReview":
		s["allOf"] = append(list(s["allOf"]), object{"if": object{"properties": object{"event": object{"enum": []string{"REQUEST_CHANGES", "COMMENT"}}}, "required": []string{"event"}}, "then": object{"required": []string{"body"}, "properties": object{"body": object{"type": "string", "minLength": 1}}}})
	}
}
