extends SceneTree

const CANONICAL_JSON: Script = preload("res://scripts/canonical_json.gd")


func _initialize() -> void:
	var ordered: Dictionary = {
		"z": 0,
		"é": "slash/line\u2028",
		"a": [true, false, null, -12],
	}
	if not _require(
		_text(ordered) == "{\"a\":[true,false,null,-12],\"z\":0,\"é\":\"slash/line\u2028\"}",
		"Object keys or literal encoding do not follow the canonical form."
	):
		return
	var reversed: Dictionary = {
		"a": [true, false, null, -12],
		"é": "slash/line\u2028",
		"z": 0,
	}
	if not _require(
		_text(ordered) == _text(reversed),
		"Dictionary insertion order changed canonical output."
	):
		return
	if not _require(
		_text("\"\\/\b\f\n\r\t\u0001") == "\"\\\"\\\\/\\u0008\\u000c\\u000a\\u000d\\u0009\\u0001\"",
		"String escaping does not match the required lowercase control escapes."
	):
		return
	var digest: Dictionary = CANONICAL_JSON.sha256({"a": 1})
	if not _require(
		digest.get("digest") == "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862",
		"SHA-256 digest did not use the canonical UTF-8 bytes."
	):
		return
	var invalid_values: Array[Variant] = [
		1.0,
		{"valid": 1, 3: "invalid key"},
		{"nested": [1, 2.0]},
	]
	for invalid: Variant in invalid_values:
		if not _require(
			not CANONICAL_JSON.encode(invalid).get("ok", false),
			"An unsupported canonical JSON value was accepted."
		):
			return

	print("Canonical JSON checks passed.")
	quit(0)


func _text(value: Variant) -> String:
	var result: Dictionary = CANONICAL_JSON.encode(value)
	if not result.get("ok", false):
		push_error(str(result.get("error", "Canonical encoding failed.")))
		quit(1)
		return ""
	return result["text"]


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false
