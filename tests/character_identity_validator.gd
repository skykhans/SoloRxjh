extends SceneTree

const VALIDATOR: Script = preload("res://scripts/character_identity_validator.gd")
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


func _initialize() -> void:
	for class_id: String in CLASS_IDS:
		var identity: Dictionary = _identity(
			class_id,
			"female" if class_id == "dongling_shennv" else "male"
		)
		if not _require(
			VALIDATOR.validate(identity).get("ok", false),
			"Valid identity was rejected for %s." % class_id
		):
			return
		if class_id not in ["lu_fenglang", "zhen_fengbai", "dongling_shennv"]:
			var alternate: Dictionary = _identity(
				class_id,
				"female" if identity["appearance"]["body_type"] == "male" else "male"
			)
			if not _require(
				VALIDATOR.validate(alternate).get("ok", false),
				"Flexible body type was rejected for %s." % class_id
			):
				return

	var decomposed: Dictionary = _identity("sword", "male")
	decomposed["name"] = "e\u0301乙"
	if not _require(
		not VALIDATOR.validate(decomposed).get("ok", false),
		"A non-NFC persistent name was accepted."
	):
		return
	var normalized: Dictionary = _identity("sword", "male")
	normalized["name"] = "é乙"
	if not _require(
		VALIDATOR.validate(normalized).get("name_comparison_key") == "é乙",
		"A normalized Unicode comparison key was not produced."
	):
		return

	var invalid_identity: Dictionary = _identity("lu_fenglang", "female")
	var invalid_class: Dictionary = _identity("unknown_class", "male")
	var extra_key: Dictionary = _identity("sword", "male")
	extra_key["appearance"]["hair_color"] = "black"
	var bad_appearance: Dictionary = _identity("sword", "male")
	bad_appearance["appearance"]["skin_tone_id"] = "unknown"
	var non_string_appearance: Dictionary = _identity("sword", "male")
	non_string_appearance["appearance"]["hairstyle_id"] = 3
	var invalid_times: Array[String] = [
		"0000-01-01T00:00:00Z",
		"2026-02-29T12:00:00Z",
		"2100-02-29T12:00:00Z",
		"2026-04-31T12:00:00Z",
		"2024-01-01T24:00:00Z",
		"2024-01-01T00:00:60Z",
		"2024-01-01T00:00:00.0Z",
	]
	if not _require(
		not VALIDATOR.validate(invalid_identity).get("ok", false)
			and not VALIDATOR.validate(invalid_class).get("ok", false)
			and not VALIDATOR.validate(extra_key).get("ok", false)
			and not VALIDATOR.validate(bad_appearance).get("ok", false)
			and not VALIDATOR.validate(non_string_appearance).get("ok", false),
		"An invalid body type, class, extra field, or appearance choice was accepted."
	):
		return
	for timestamp: String in invalid_times:
		var identity: Dictionary = _identity("sword", "male")
		identity["created_at_utc"] = timestamp
		if not _require(
			not VALIDATOR.validate(identity).get("ok", false),
			"An invalid UTC timestamp was accepted: %s" % timestamp
		):
			return
	for timestamp: String in [
		"2000-02-29T23:59:59Z",
		"2024-02-29T00:00:00Z",
		"2026-11-16T12:34:56Z",
	]:
		var identity: Dictionary = _identity("sword", "male")
		identity["created_at_utc"] = timestamp
		if not _require(
			VALIDATOR.validate(identity).get("ok", false),
			"A valid UTC timestamp was rejected: %s" % timestamp
		):
			return

	print("Character identity validation checks passed.")
	quit(0)


func _identity(class_id: String, body_type: String) -> Dictionary:
	return {
		"character_id": "character:test",
		"name": "青竹",
		"class_id": class_id,
		"appearance": {
			"body_type": body_type,
			"skin_tone_id": "warm",
			"hairstyle_id": "high_knot",
			"outfit_palette_id": "indigo",
		},
		"created_at_utc": "2026-11-16T12:34:56Z",
	}


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false
