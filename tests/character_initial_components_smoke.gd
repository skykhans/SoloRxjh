extends SceneTree

const CATALOG: Script = preload("res://scripts/character_template_catalog.gd")
const JSON_SCHEMA_VALIDATOR: Script = preload("res://scripts/json_schema_validator.gd")


func _initialize() -> void:
	var result: Dictionary = CATALOG.resolve_initial_components()
	if not _require(
		result.get("ok", false) and result.get("components") is Dictionary,
		"Character initial components could not be resolved: %s" % result.get("error", "")
	):
		return
	var components: Dictionary = result["components"]
	if not _require(
		components.size() == 14
			and components["training_gate_buffs"] == {"by_world": {}}
			and components["training_gate_daily"] == {"by_world": {}}
			and components["earth_spirit_points"].is_empty()
			and components["qigong"].size() == 8
			and components["customization"]["revision"] == 0
			and components["pending_play_session"] == null,
		"Resolved initial components do not match their registered root values."
	):
		return
	var copied_training_state: Dictionary = components["training_gate_buffs"]
	var template: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://docs/contracts/角色初始模板.v1.json")
	)
	var template_training_state: Dictionary = template["initial_state_profile"][
		"training_gate_buffs"
	]
	if not _require(
		template_training_state == copied_training_state,
		"Resolved training state differs from its declared owner value."
	):
		return
	copied_training_state["by_world"]["mutation_probe"] = {}
	if not _require(
		not template_training_state["by_world"].has("mutation_probe"),
		"Initial component results shared mutable state."
	):
		return
	var validator: RefCounted = JSON_SCHEMA_VALIDATOR.new()
	var session_schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://docs/contracts/角色会话.schema.json"
	))
	var null_guard_result: Dictionary = validator.validate(null, session_schema)
	var invalid_guard_result: Dictionary = validator.validate("active", session_schema)
	if not _require(
		null_guard_result.get("ok", false) and not invalid_guard_result.get("ok", false),
		"Session schema did not accept null while rejecting a malformed guard."
	):
		return
	var customization_schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://docs/contracts/角色配置根.schema.json"
	))
	var customization: Dictionary = {
		"format_version": 1,
		"revision": 0,
		"explicit": {},
		"latest_event_ref": null,
	}
	var valid_customization: Dictionary = validator.validate(
		customization,
		customization_schema
	)
	customization["unexpected"] = true
	var invalid_customization: Dictionary = validator.validate(
		customization,
		customization_schema
	)
	if not _require(
		valid_customization.get("ok", false)
			and not invalid_customization.get("ok", false),
		"Customization schema did not enforce its closed four-key root."
	):
		return
	print("Character initial component resolution smoke test passed.")
	quit(0)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false
