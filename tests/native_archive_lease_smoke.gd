extends SceneTree


func _initialize() -> void:
	if not ClassDB.class_exists("WindowsArchiveLease"):
		_fail("WindowsArchiveLease GDExtension did not load.")
		return

	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 1:
		_fail("Expected an isolated test root path.")
		return

	var profiles_directory: String = arguments[0].path_join("profiles")
	var make_directory_error: Error = DirAccess.make_dir_recursive_absolute(profiles_directory)
	if not _require(make_directory_error == OK, "Could not create the isolated profiles directory."):
		return

	var profile_id: String = "profile_" + "a".repeat(32)
	var directory_lease: WindowsArchiveLease = WindowsArchiveLease.new()
	var directory_result: Dictionary = directory_lease.try_acquire(profiles_directory)
	if not _require(directory_result.get("ok") == true, "Could not acquire the directory lease: %s" % directory_result):
		return

	var profile_lease: WindowsArchiveLease = WindowsArchiveLease.new()
	var profile_result: Dictionary = profile_lease.try_acquire(profiles_directory, profile_id)
	if not _require(profile_result.get("ok") == true, "Could not acquire the profile lease: %s" % profile_result):
		directory_lease.release()
		return

	if not _require(
		_run_worker(profiles_directory, profile_id, "directory", "blocked") == 0,
		"A second process acquired the held directory lease."
	):
		profile_lease.release()
		directory_lease.release()
		return
	if not _require(
		_run_worker(profiles_directory, profile_id, "profile", "blocked") == 0,
		"A second process acquired the held profile lease."
	):
		profile_lease.release()
		directory_lease.release()
		return

	var target_name: String = "%s.json" % profile_id
	var contents: PackedByteArray = "{\"revision\":1}".to_utf8_buffer()
	var create_result: Dictionary = directory_lease.publish_bytes(
		profiles_directory,
		".p2-smoke-create.tmp",
		target_name,
		contents,
		false
	)
	if not _require(create_result.get("ok") == true, "No-overwrite publication failed: %s" % create_result):
		profile_lease.release()
		directory_lease.release()
		return
	if not _require(_read_bytes(profiles_directory.path_join(target_name)) == contents, "Published bytes differ from the candidate."):
		profile_lease.release()
		directory_lease.release()
		return

	var denied_overwrite: Dictionary = directory_lease.publish_bytes(
		profiles_directory,
		".p2-smoke-overwrite.tmp",
		target_name,
		"{\"revision\":2}".to_utf8_buffer(),
		false
	)
	if not _require(
		denied_overwrite.get("ok") == false and denied_overwrite.get("error") == "publish_target_exists",
		"Existing profile publication was not rejected: %s" % denied_overwrite
	):
		profile_lease.release()
		directory_lease.release()
		return
	if not _require(_read_bytes(profiles_directory.path_join(target_name)) == contents, "A rejected publication changed the profile."):
		profile_lease.release()
		directory_lease.release()
		return

	var replace_result: Dictionary = directory_lease.publish_bytes(
		profiles_directory,
		".p2-smoke-replace.tmp",
		target_name,
		"{\"revision\":2}".to_utf8_buffer(),
		true
	)
	if not _require(replace_result.get("ok") == true, "Atomic replacement failed: %s" % replace_result):
		profile_lease.release()
		directory_lease.release()
		return
	if not _require(
		_read_bytes(profiles_directory.path_join(target_name)) == "{\"revision\":2}".to_utf8_buffer(),
		"Atomic replacement did not publish the complete new contents."
	):
		profile_lease.release()
		directory_lease.release()
		return

	profile_lease.release()
	if not _require(
		_run_worker(profiles_directory, profile_id, "profile", "acquired") == 0,
		"A profile lease remained locked after release."
	):
		directory_lease.release()
		return

	directory_lease.release()
	if not _require(
		_run_worker(profiles_directory, profile_id, "directory", "acquired") == 0,
		"A directory lease remained locked after release."
	):
		return

	_remove_test_file(profiles_directory.path_join(target_name))
	_remove_test_file(profiles_directory.path_join(".directory.lock"))
	_remove_test_file(profiles_directory.path_join("%s.lock" % profile_id))
	if not _require(
		DirAccess.remove_absolute(profiles_directory) == OK,
		"Could not remove the isolated profiles directory."
	):
		return
	var test_root: String = profiles_directory.get_base_dir()
	if not _require(DirAccess.remove_absolute(test_root) == OK, "Could not remove the isolated test root."):
		return

	print("Windows archive lease smoke test passed.")
	quit(0)


func _run_worker(profiles_directory: String, profile_id: String, lock_kind: String, expected: String) -> int:
	var output: Array = []
	var project_directory: String = ProjectSettings.globalize_path("res://")
	var arguments: PackedStringArray = [
		"--headless",
		"--path",
		project_directory,
		"--script",
		"res://tests/native_archive_lease_worker.gd",
		"--",
		profiles_directory,
		profile_id,
		lock_kind,
		expected,
	]
	var exit_code: int = OS.execute(OS.get_executable_path(), arguments, output, true)
	if not output.is_empty():
		print("\n".join(output))
	return exit_code


func _read_bytes(path: String) -> PackedByteArray:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	return file.get_buffer(file.get_length())


func _remove_test_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
