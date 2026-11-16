extends SceneTree

const ARCHIVE_REPOSITORY: Script = preload("res://scripts/archive_repository.gd")


func _initialize() -> void:
	var expected_profiles_directory: String = (
		"C:/Users/Tester/AppData/Local/SoloRxjh/profiles"
	)
	if not _require(
		ARCHIVE_REPOSITORY.default_profiles_directory("C:/Users/Tester/AppData/Local")
			== expected_profiles_directory
			and ARCHIVE_REPOSITORY.default_profiles_directory("").is_empty(),
		"Default profile directory does not match the Windows storage contract."
	):
		return

	if not _require(
		ClassDB.class_exists("WindowsArchiveLease"),
		"WindowsArchiveLease GDExtension did not load."
	):
		return

	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if not _require(arguments.size() == 1, "Expected an isolated test root path."):
		return
	var profiles_directory: String = arguments[0].path_join("profiles")
	var repository: RefCounted = ARCHIVE_REPOSITORY.new(profiles_directory)
	var normalizer: WindowsArchiveLease = WindowsArchiveLease.new()

	var normalized_name: Dictionary = normalizer.normalize_profile_name("  e\u0301乙  ")
	if not _require(
		normalized_name.get("ok", false)
			and normalized_name.get("profile_name") == "é乙"
			and normalizer.normalize_profile_name("甲\n乙").get("ok", true) == false,
		"Profile name canonicalization failed."
	):
		return

	var empty_catalog: Dictionary = repository.list_profiles()
	if not _require(
		empty_catalog.get("ok", false)
			and empty_catalog.get("all_valid", false)
			and empty_catalog.get("profiles", []).is_empty(),
		"An empty profile directory was not accepted."
	):
		return

	var first: Dictionary = repository.create_profile("甲乙")
	if not _require(first.get("ok", false), "First profile creation failed: %s" % first):
		return
	if not _require(
		first["profile"]["data"].size() == 75
			and first["profile"]["data"]["revision"] == 1
			and first["profile"]["data"]["settings"]["master_volume"] == 0.7
			and first["profile"]["data"]["characters"].is_empty()
			and first["profile"]["data"]["worlds"].is_empty(),
		"Created profile does not match the complete empty-profile initial state."
	):
		return

	var duplicate: Dictionary = repository.create_profile(" 甲乙 ")
	if not _require(not duplicate.get("ok", false), "A duplicate normalized profile name was accepted."):
		return

	var second: Dictionary = repository.create_profile("丙丁")
	var third: Dictionary = repository.create_profile("戊己")
	if not _require(
		second.get("ok", false) and third.get("ok", false),
		"Profile capacity could not be filled: %s, %s" % [second, third]
	):
		return
	var over_capacity: Dictionary = repository.create_profile("庚辛")
	if not _require(not over_capacity.get("ok", false), "A fourth profile was accepted."):
		return

	var profile_file: FileAccess = FileAccess.open(
		profiles_directory.path_join("broken.json"),
		FileAccess.WRITE
	)
	if not _require(profile_file != null, "Could not create an isolated corrupt-candidate fixture."):
		return
	profile_file.store_string("{")
	profile_file.close()

	var corrupt_catalog: Dictionary = repository.list_profiles()
	var blocked_create: Dictionary = repository.create_profile("壬癸")
	if not _require(
		corrupt_catalog.get("all_valid", true) == false
			and not blocked_create.get("ok", false)
			and corrupt_catalog["profiles"].size() == 4,
		"A corrupt JSON candidate did not occupy capacity and block writes."
	):
		return

	print("P2 empty profile lifecycle smoke test passed.")
	quit(0)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false
