extends SceneTree

const ARCHIVE_REPOSITORY: Script = preload("res://scripts/archive_repository.gd")
const ARCHIVE_FILE_LEASE: Script = preload("res://scripts/archive_file_lease.gd")


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if not _require(arguments.size() == 1, "Expected an isolated test root path."):
		return
	var profiles_directory: String = arguments[0].path_join("profiles")
	var repository: RefCounted = ARCHIVE_REPOSITORY.new(profiles_directory)
	var rejected_settings: Dictionary = ARCHIVE_REPOSITORY.new(
		profiles_directory.path_join("invalid")
	).create_profile("非法设置", {"master_volume": 2.0})
	if not _require(
		not rejected_settings.get("ok", false),
		"An incomplete creation settings object was accepted."
	):
		return
	var initial_settings: Dictionary = {
		"master_volume": 0.35,
		"music_volume": 0.7,
		"sfx_volume": 0.8,
		"ui_volume": 0.25,
		"camera_distance": 8.0,
		"window_mode": "windowed",
		"window_resolution": [1280, 720],
		"graphics_preset": "medium",
		"vsync_enabled": true,
	}
	var created: Dictionary = repository.create_profile("设置测试", initial_settings)
	if not _require(created.get("ok", false), "Could not create settings fixture: %s" % created):
		return

	var profile: Dictionary = created["profile"]
	if not _require(
		profile["revision"] == 1
			and profile["data"]["settings"] == initial_settings
			and repository.list_profiles().get("profiles", []).size() == 1,
		"Initial settings were not stored in the one new profile publication."
	):
		return
	var profile_id: String = profile["profile_id"]
	var expected_data: Dictionary = profile["data"].duplicate(true)
	var settings: Dictionary = expected_data["settings"].duplicate(true)
	settings["master_volume"] = 0.4
	settings["music_volume"] = 0.6
	settings["sfx_volume"] = 0.8
	settings["ui_volume"] = 0.2
	settings["camera_distance"] = 9
	settings["window_mode"] = "borderless_fullscreen"
	settings["window_resolution"] = [1920, 1080]
	settings["graphics_preset"] = "high"
	settings["vsync_enabled"] = false
	expected_data["settings"] = settings.duplicate(true)
	expected_data["revision"] = 2

	var saved: Dictionary = repository.save_profile_settings(profile_id, 1, settings)
	var catalog: Dictionary = repository.list_profiles()
	var saved_profile: Dictionary = _find_profile(catalog, profile_id)
	var saved_data: Dictionary = saved_profile.get("data", {})
	var stored_revision: int = int(saved_profile.get("revision", -1))
	if not _require(
		saved.get("ok", false)
			and saved.get("changed", false)
			and stored_revision == 2
			and _profiles_equal(saved_data, expected_data),
		"Saving settings did not preserve the full profile and increment revision once: %s" % saved
	):
		return

	var same_settings: Dictionary = saved_profile["data"]["settings"].duplicate(true)
	var no_op: Dictionary = repository.save_profile_settings(profile_id, 2, same_settings)
	if not _require(
		no_op.get("ok", false)
			and not no_op.get("changed", true)
			and no_op.get("profile", {}).get("revision") == 2,
		"Saving identical settings changed the profile revision."
	):
		return

	var stale: Dictionary = repository.save_profile_settings(profile_id, 1, settings)
	var invalid_settings: Dictionary = settings.duplicate(true)
	invalid_settings["master_volume"] = 1.01
	var invalid: Dictionary = repository.save_profile_settings(profile_id, 2, invalid_settings)
	var unchanged_data: Dictionary = _find_profile(
		repository.list_profiles(),
		profile_id
	).get("data", {})
	if not _require(
		not stale.get("ok", false)
			and not invalid.get("ok", false)
			and _profiles_equal(unchanged_data, expected_data),
		"A stale revision or invalid settings value changed the stored profile."
	):
		return

	var held_lease: Variant = ARCHIVE_FILE_LEASE.new()
	var held: Dictionary = held_lease.try_acquire(profiles_directory, profile_id)
	if not _require(held.get("ok", false), "Could not hold profile lease fixture."):
		return
	var blocked: Dictionary = repository.save_profile_settings(profile_id, 2, settings)
	var released: bool = held_lease.release()
	unchanged_data = _find_profile(repository.list_profiles(), profile_id).get("data", {})
	if not _require(
		not blocked.get("ok", false)
			and released
			and _profiles_equal(unchanged_data, expected_data),
		"Settings changed a profile while its exclusive lease was held."
	):
		return

	print("P2 archive profile settings smoke test passed.")
	quit(0)


func _find_profile(catalog: Dictionary, profile_id: String) -> Dictionary:
	for profile: Dictionary in catalog.get("profiles", []):
		if profile.get("profile_id") == profile_id:
			return profile
	return {}


func _profiles_equal(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size():
		return false
	for key: Variant in expected:
		if not actual.has(key):
			return false
		if actual[key] is Dictionary and expected[key] is Dictionary:
			if not _profiles_equal(actual[key], expected[key]):
				return false
		elif actual[key] is Array and expected[key] is Array:
			if not _arrays_equal(actual[key], expected[key]):
				return false
		elif typeof(actual[key]) in [TYPE_INT, TYPE_FLOAT] and typeof(expected[key]) in [TYPE_INT, TYPE_FLOAT]:
			if float(actual[key]) != float(expected[key]):
				return false
		elif actual[key] != expected[key]:
			return false
	return true


func _arrays_equal(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for index: int in range(expected.size()):
		var actual_value: Variant = actual[index]
		var expected_value: Variant = expected[index]
		if actual_value is Dictionary and expected_value is Dictionary:
			if not _profiles_equal(actual_value, expected_value):
				return false
		elif actual_value is Array and expected_value is Array:
			if not _arrays_equal(actual_value, expected_value):
				return false
		elif typeof(actual_value) in [TYPE_INT, TYPE_FLOAT] and typeof(expected_value) in [TYPE_INT, TYPE_FLOAT]:
			if float(actual_value) != float(expected_value):
				return false
		elif actual_value != expected_value:
			return false
	return true


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false
