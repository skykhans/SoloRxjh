extends RefCounted

const UNICODE_NORMALIZER: Script = preload("res://scripts/unicode15_normalizer.gd")
const CLASS_IDS: Array[String] = [
	"blade",
	"sword",
	"spear",
	"physician",
	"archer",
	"assassin",
	"musician",
	"fighter",
	"han_feiguan",
	"tan_hualing",
	"mei_liuzhen",
	"lu_fenglang",
	"dongling_shennv",
	"zhen_fengbai",
]
const SKIN_TONE_IDS: Array[String] = ["ivory", "warm", "bronze", "brown", "deep"]
const HAIRSTYLE_IDS: Array[String] = ["high_knot", "half_tied", "short_swept"]
const OUTFIT_PALETTE_IDS: Array[String] = [
	"indigo",
	"crimson",
	"jade",
	"ochre",
	"plum",
	"ink",
]


static func validate(identity: Variant) -> Dictionary:
	if not identity is Dictionary or not _has_exact_keys(identity, [
		"character_id",
		"name",
		"class_id",
		"appearance",
		"created_at_utc",
	]):
		return _failure("Character identity must match the strict five-key root.")
	if (
		typeof(identity["character_id"]) != TYPE_STRING
		or identity["character_id"].strip_edges().is_empty()
	):
		return _failure("Character ID is invalid.")
	if typeof(identity["name"]) != TYPE_STRING:
		return _failure("Character name must be a string.")
	var name_result: Dictionary = UNICODE_NORMALIZER.normalize_character_name(
		identity["name"]
	)
	if (
		not name_result.get("ok", false)
		or name_result["character_name"] != identity["name"]
	):
		return _failure("Character name is not a normalized valid name.")
	if typeof(identity["class_id"]) != TYPE_STRING or not CLASS_IDS.has(identity["class_id"]):
		return _failure("Character class is not one of the fourteen supported identities.")
	if not identity["appearance"] is Dictionary or not _has_exact_keys(
		identity["appearance"],
		["body_type", "skin_tone_id", "hairstyle_id", "outfit_palette_id"]
	):
		return _failure("Character appearance must match its strict four-key root.")
	var appearance: Dictionary = identity["appearance"]
	if (
		typeof(appearance["body_type"]) != TYPE_STRING
		or typeof(appearance["skin_tone_id"]) != TYPE_STRING
		or typeof(appearance["hairstyle_id"]) != TYPE_STRING
		or typeof(appearance["outfit_palette_id"]) != TYPE_STRING
		or
		not appearance["body_type"] in ["male", "female"]
		or not SKIN_TONE_IDS.has(appearance["skin_tone_id"])
		or not HAIRSTYLE_IDS.has(appearance["hairstyle_id"])
		or not OUTFIT_PALETTE_IDS.has(appearance["outfit_palette_id"])
	):
		return _failure("Character appearance contains an unknown choice.")
	if (
		identity["class_id"] in ["lu_fenglang", "zhen_fengbai"]
		and appearance["body_type"] != "male"
	):
		return _failure("This class only supports the male body type.")
	if (
		identity["class_id"] == "dongling_shennv"
		and appearance["body_type"] != "female"
	):
		return _failure("Dongling Shennv only supports the female body type.")
	if not is_valid_utc_seconds(identity["created_at_utc"]):
		return _failure("Character creation time must be a real UTC calendar second.")
	return {
		"ok": true,
		"identity": identity.duplicate(true),
		"name_comparison_key": name_result["comparison_key"],
	}


static func is_valid_utc_seconds(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != 20:
		return false
	var text: String = value
	if (
		text[4] != "-"
		or text[7] != "-"
		or text[10] != "T"
		or text[13] != ":"
		or text[16] != ":"
		or text[19] != "Z"
	):
		return false
	for index: int in range(text.length()):
		if index in [4, 7, 10, 13, 16, 19]:
			continue
		if text.unicode_at(index) < 48 or text.unicode_at(index) > 57:
			return false
	var year: int = int(text.substr(0, 4))
	var month: int = int(text.substr(5, 2))
	var day: int = int(text.substr(8, 2))
	var hour: int = int(text.substr(11, 2))
	var minute: int = int(text.substr(14, 2))
	var second: int = int(text.substr(17, 2))
	if year < 1 or month < 1 or month > 12 or hour > 23 or minute > 59 or second > 59:
		return false
	var days_by_month: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if month == 2 and _is_leap_year(year):
		days_by_month[1] = 29
	return day >= 1 and day <= days_by_month[month - 1]


static func _is_leap_year(year: int) -> bool:
	return year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)


static func _has_exact_keys(value: Dictionary, expected_keys: Array) -> bool:
	if value.size() != expected_keys.size():
		return false
	for key: String in expected_keys:
		if not value.has(key):
			return false
	return true


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
	}
