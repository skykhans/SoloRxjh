extends SceneTree

const APP_SCRIPT: Script = preload("res://scripts/app.gd")
const CONFIG_LOADER: Script = preload("res://scripts/config_loader.gd")
const REQUIRED_INPUT_ACTIONS: PackedStringArray = [
	"move_forward",
	"move_left",
	"move_back",
	"move_right",
	"run",
	"world_click",
	"camera_orbit",
	"camera_zoom_in",
	"camera_zoom_out",
	"normal_attack",
	"skill_1",
	"skill_2",
	"skill_3",
	"skill_4",
	"dodge",
	"target_cycle",
	"interact",
	"pickup",
	"use_life_potion",
	"use_mana_potion",
	"use_return_scroll",
	"open_inventory",
	"open_character",
	"open_skills",
	"open_quests",
	"open_blacksmith",
	"open_sect",
	"open_map",
	"open_chat",
	"close_or_pause",
	"collision_debug",
	"open_character_config",
]
const EXPECTED_KEY_BINDINGS: Dictionary = {
	"move_forward": KEY_W,
	"move_left": KEY_A,
	"move_back": KEY_S,
	"move_right": KEY_D,
	"run": KEY_SHIFT,
	"normal_attack": KEY_J,
	"skill_1": KEY_Q,
	"skill_2": KEY_R,
	"skill_3": KEY_G,
	"skill_4": KEY_V,
	"dodge": KEY_SPACE,
	"target_cycle": KEY_TAB,
	"interact": KEY_E,
	"pickup": KEY_F,
	"use_life_potion": KEY_1,
	"use_mana_potion": KEY_2,
	"use_return_scroll": KEY_3,
	"open_inventory": KEY_B,
	"open_character": KEY_C,
	"open_skills": KEY_K,
	"open_quests": KEY_T,
	"open_blacksmith": KEY_U,
	"open_sect": KEY_H,
	"open_map": KEY_M,
	"open_chat": KEY_ENTER,
	"close_or_pause": KEY_ESCAPE,
	"collision_debug": KEY_F3,
	"open_character_config": KEY_F8,
}
const EXPECTED_MOUSE_BINDINGS: Dictionary = {
	"world_click": MOUSE_BUTTON_LEFT,
	"camera_orbit": MOUSE_BUTTON_RIGHT,
	"camera_zoom_in": MOUSE_BUTTON_WHEEL_UP,
	"camera_zoom_out": MOUSE_BUTTON_WHEEL_DOWN,
}


func _initialize() -> void:
	if not _require(
		APP_SCRIPT.validate_engine_version().is_empty(),
		"Engine version mismatch: %s" % Engine.get_version_info()
	):
		return
	if not _require(
		ProjectSettings.get_setting("physics/common/physics_ticks_per_second") == 60,
		"Physics tick rate is not 60 Hz."
	):
		return
	if not _require(ResourceLoader.exists("res://scenes/main.tscn"), "Main scene is missing."):
		return

	for action: String in REQUIRED_INPUT_ACTIONS:
		if not _require(InputMap.has_action(action), "Missing InputMap action: %s" % action):
			return
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		if not _require(not events.is_empty(), "InputMap action has no event: %s" % action):
			return
		if EXPECTED_KEY_BINDINGS.has(action):
			var key_event: InputEventKey = events[0] as InputEventKey
			if not _require(
				key_event != null
					and key_event.physical_keycode == EXPECTED_KEY_BINDINGS[action],
				"InputMap key mismatch: %s expected=%s actual=%s" % [
					action,
					EXPECTED_KEY_BINDINGS[action],
					key_event.physical_keycode if key_event != null else "not a key",
				]
			):
				return
		elif EXPECTED_MOUSE_BINDINGS.has(action):
			var mouse_event: InputEventMouseButton = events[0] as InputEventMouseButton
			if not _require(
				mouse_event != null
					and mouse_event.button_index == EXPECTED_MOUSE_BINDINGS[action],
				"InputMap mouse binding mismatch: %s" % action
			):
				return

	var config_error: String = APP_SCRIPT.validate_runtime_config()
	if config_error.is_empty():
		print("P1_CONFIG_STATUS=valid")
	elif config_error.contains("正式 JSON 配置"):
		print("P1_CONFIG_STATUS=missing")
	else:
		_fail("Unexpected runtime configuration result: %s" % config_error)
		return

	var missing_directory_error: String = APP_SCRIPT.validate_runtime_config(
		"res://tests/fixtures/p1-missing-config"
	)
	if not _require(
		missing_directory_error == "缺少正式 JSON 配置目录：res://tests/fixtures/p1-missing-config",
		"Missing configuration directory was not rejected: %s" % missing_directory_error
	):
		return
	if not _require(
		APP_SCRIPT.validate_runtime_config("res://tests/fixtures/p1-valid-config").is_empty(),
		"Valid nested JSON configuration was rejected."
	):
		return

	var resource_error: String = APP_SCRIPT.validate_resource_manifest()
	if not _require(resource_error.is_empty(), "Formal resource manifest failed: %s" % resource_error):
		return
	var resource_file: FileAccess = FileAccess.open(
		"res://assets/config/resources.json",
		FileAccess.READ
	)
	if not _require(resource_file != null, "Formal resource manifest is missing."):
		return
	var resource_json: JSON = JSON.new()
	if not _require(
		resource_json.parse(resource_file.get_as_text()) == OK,
		"Formal resource manifest is invalid JSON."
	):
		return
	var resource_manifest: Dictionary = resource_json.data
	if not _require(
		resource_manifest["resources"].size() == 19,
		"Formal resource manifest does not enumerate all 19 runtime assets."
	):
		return
	var malformed_manifest: Dictionary = resource_manifest.duplicate(true)
	malformed_manifest["resources"][1]["id"] = malformed_manifest["resources"][0]["id"]
	var manifest_error: String = CONFIG_LOADER.validate_manifest(malformed_manifest)
	if not _require(
		manifest_error.contains("重复 ID"),
		"Duplicate resource IDs were not rejected: %s" % manifest_error
	):
		return
	malformed_manifest = resource_manifest.duplicate(true)
	malformed_manifest["resources"][0]["path"] = "res://assets/../Cargo.toml"
	manifest_error = CONFIG_LOADER.validate_manifest(malformed_manifest)
	if not _require(
		manifest_error.contains("path"),
		"Resource traversal was not rejected: %s" % manifest_error
	):
		return
	malformed_manifest = resource_manifest.duplicate(true)
	malformed_manifest["unexpected"] = true
	manifest_error = CONFIG_LOADER.validate_manifest(malformed_manifest)
	if not _require(
		manifest_error.contains("format_version"),
		"Unknown manifest fields were not rejected: %s" % manifest_error
	):
		return

	var syntax_error: String = APP_SCRIPT.validate_runtime_config(
		"res://tests/fixtures/p1-invalid-syntax"
	)
	if not _require(
		syntax_error.begins_with("正式 JSON 配置格式错误："),
		"Malformed JSON configuration was accepted: %s" % syntax_error
	):
		return
	var root_error: String = APP_SCRIPT.validate_runtime_config("res://tests/fixtures/p1-invalid-root")
	if not _require(
		root_error.begins_with("正式 JSON 配置根节点必须是对象："),
		"Non-object JSON configuration was accepted: %s" % root_error
	):
		return
	print("P1 runtime probe passed.")
	quit(0)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
