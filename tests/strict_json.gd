extends SceneTree

const STRICT_JSON: Script = preload("res://scripts/strict_json.gd")


func _initialize() -> void:
	var duplicate_documents: Array[String] = [
		"{\"a\":1,\"a\":2}",
		"{\"outer\":{\"x\":1,\"x\":2}}",
		"{\"a\":1,\"\\u0061\":2}",
		"[{\"x\":1,\"x\":2}]",
	]
	for document: String in duplicate_documents:
		if not _require(
			STRICT_JSON.has_duplicate_object_keys(document),
			"A duplicate object key was not detected."
		):
			return
	var unique_documents: Array[String] = [
		"{\"a\":1,\"b\":{\"x\":2,\"y\":3}}",
		"{\"text\":\"commas, braces { } and escaped quote \\\" stay inside a string\"}",
		"{\"a\":1,\"\\u0062\":2}",
		"[1,true,null,{\"slash\":\"\\/\"}]",
	]
	for document: String in unique_documents:
		if not _require(
			not STRICT_JSON.has_duplicate_object_keys(document),
			"A unique-key JSON document was rejected."
		):
			return
	for document: String in [
		"{\"revision\":1,\"settings\":{\"value\":1.0}}",
		"{\"nested\":{\"revision\":1.0},\"revision\":-12}",
	]:
		if not _require(
			STRICT_JSON.has_integer_object_field_token(document, "revision"),
			"An integer top-level field token was rejected."
		):
			return
	for document: String in [
		"{\"revision\":1.0}",
		"{\"revision\":1e0}",
		"{\"revision\":true}",
		"{\"nested\":{\"revision\":1}}",
	]:
		if not _require(
			not STRICT_JSON.has_integer_object_field_token(document, "revision"),
			"A non-integer or nested field token was accepted."
		):
			return
	for index: int in range(2):
		if not _require(
			STRICT_JSON.has_nested_integer_array_item_token(
				"{\"settings\":{\"window_resolution\":[1600,900],\"other\":[1.0]}}",
				"settings",
				"window_resolution",
				index
			),
			"A valid integer array item token was rejected."
		):
			return
	for invalid_resolution: Array in [
		["{\"settings\":{\"window_resolution\":[1600.0,900]}}", 0],
		["{\"settings\":{\"window_resolution\":[1600,900e0]}}", 1],
		["{\"outer\":{\"settings\":{\"window_resolution\":[1600,900]}}}", 1],
		["{\"settings\":{\"window_resolution\":[1600]}}", 1],
	]:
		if not _require(
			not STRICT_JSON.has_nested_integer_array_item_token(
				invalid_resolution[0],
				"settings",
				"window_resolution",
				invalid_resolution[1]
			),
			"A non-integer, nested, or missing array item token was accepted."
		):
			return

	print("Strict JSON duplicate-key checks passed.")
	quit(0)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false
