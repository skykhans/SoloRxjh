extends SceneTree

const APPLICATION: Script = preload("res://scripts/app.gd")


func _initialize() -> void:
	var current_directory_access: DirAccess = DirAccess.open(".")
	if not _require(current_directory_access != null, "Could not open the working directory."):
		return
	var working_directory: String = current_directory_access.get_current_dir().simplify_path()
	var relative_result: Dictionary = APPLICATION.parse_startup_arguments(
		PackedStringArray(["--save-dir", "target/verification/profile-root"]),
		working_directory
	)
	var expected_relative_profiles: String = working_directory.path_join(
		"target/verification/profile-root/profiles"
	).simplify_path()
	if not _require(
		relative_result.get("ok", false)
			and relative_result.get("profiles_directory") == expected_relative_profiles,
		"Relative --save-dir was not resolved from the working directory."
	):
		return

	var absolute_root: String = working_directory.path_join("absolute-profile-root").simplify_path()
	var absolute_result: Dictionary = APPLICATION.parse_startup_arguments(
		PackedStringArray(["--save-dir", absolute_root]),
		working_directory
	)
	if not _require(
		absolute_result.get("ok", false)
			and absolute_result.get("profiles_directory")
				== absolute_root.path_join("profiles"),
		"Absolute --save-dir was not preserved."
	):
		return

	var default_result: Dictionary = APPLICATION.parse_startup_arguments(
		PackedStringArray(),
		working_directory
	)
	if not _require(
		default_result.get("ok", false)
			and default_result.get("profiles_directory") == "",
		"Default storage must remain selected when --save-dir is absent."
	):
		return

	if not _require_failure(
		PackedStringArray(["--save-dir"]),
		"缺少"
	):
		return
	if not _require_failure(
		PackedStringArray(["--save-dir", ""]),
		"缺少"
	):
		return
	if not _require_failure(
		PackedStringArray(["--save-dir", "one", "--save-dir", "two"]),
		"重复"
	):
		return
	if not _require_failure(
		PackedStringArray(["--unsupported"]),
		"不支持"
	):
		return
	if not _require_failure(
		PackedStringArray(["--save-dir", "one", "--unsupported"]),
		"不支持"
	):
		return

	print("SAVE_DIR_ARGUMENTS_SMOKE=passed")
	quit(0)


func _require_failure(arguments: PackedStringArray, message_fragment: String) -> bool:
	var result: Dictionary = APPLICATION.parse_startup_arguments(
		arguments,
		DirAccess.open(".").get_current_dir()
	)
	return _require(
		not result.get("ok", false)
			and str(result.get("error", "")).contains(message_fragment),
		"Invalid arguments were not rejected clearly: %s" % arguments
	)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false
