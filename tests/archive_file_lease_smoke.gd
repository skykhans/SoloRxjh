extends SceneTree

const ARCHIVE_FILE_LEASE: Script = preload("res://scripts/archive_file_lease.gd")


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 1:
		_fail("Expected an isolated test root path.")
		return

	var test_root: String = arguments[0]
	var profiles_directory: String = test_root.path_join("profiles")
	var make_directory_error: Error = DirAccess.make_dir_recursive_absolute(profiles_directory)
	if not _require(
		make_directory_error == OK or DirAccess.dir_exists_absolute(profiles_directory),
		"Could not create the isolated profiles directory."
	):
		return

	var profile_id: String = "profile_" + "a".repeat(32)
	var directory_lease: Variant = ARCHIVE_FILE_LEASE.new()
	var directory_result: Dictionary = directory_lease.try_acquire(profiles_directory)
	if not _require(directory_result.get("ok", false), "Could not acquire directory lease: %s" % directory_result):
		return

	var profile_lease: Variant = ARCHIVE_FILE_LEASE.new()
	var profile_result: Dictionary = profile_lease.try_acquire(profiles_directory, profile_id)
	if not _require(profile_result.get("ok", false), "Could not acquire profile lease: %s" % profile_result):
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
	var first_contents: PackedByteArray = "{\"revision\":1}".to_utf8_buffer()
	var profile_publish: Dictionary = profile_lease.publish_bytes(
		profiles_directory,
		".p2-smoke-profile-lease.tmp",
		target_name,
		first_contents,
		false
	)
	if not _require(
		not profile_publish.get("ok", true)
			and profile_publish.get("error") == "directory_lease_required",
		"A profile lease published a directory transaction."
	):
		profile_lease.release()
		directory_lease.release()
		return

	var create_result: Dictionary = directory_lease.publish_bytes(
		profiles_directory,
		".p2-smoke-create.tmp",
		target_name,
		first_contents,
		false
	)
	if not _require(create_result.get("ok", false), "No-overwrite publication failed: %s" % create_result):
		profile_lease.release()
		directory_lease.release()
		return
	if not _require(
		_read_bytes(profiles_directory.path_join(target_name)) == first_contents,
		"Published bytes differ from the candidate."
	):
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
		not denied_overwrite.get("ok", true)
			and denied_overwrite.get("error") == "publish_target_exists",
		"Existing profile publication was not rejected: %s" % denied_overwrite
	):
		profile_lease.release()
		directory_lease.release()
		return
	if not _require(
		_read_bytes(profiles_directory.path_join(target_name)) == first_contents,
		"A rejected publication changed the profile."
	):
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
	if not _require(replace_result.get("ok", false), "Atomic replacement failed: %s" % replace_result):
		profile_lease.release()
		directory_lease.release()
		return
	if not _require(
		_read_bytes(profiles_directory.path_join(target_name))
			== "{\"revision\":2}".to_utf8_buffer(),
		"Atomic replacement did not publish the complete new contents."
	):
		profile_lease.release()
		directory_lease.release()
		return

	if not _require(profile_lease.release(), "Profile lease release failed: %s" % profile_lease.get_last_error()):
		directory_lease.release()
		return
	if not _require(
		_run_worker(profiles_directory, profile_id, "profile", "acquired") == 0,
		"A released profile lease remained locked."
	):
		directory_lease.release()
		return

	if not _require(directory_lease.release(), "Directory lease release failed: %s" % directory_lease.get_last_error()):
		return
	if not _require(
		_run_worker(profiles_directory, profile_id, "directory", "acquired") == 0,
		"A released directory lease remained locked."
	):
		return

	var stale_lock_path: String = profiles_directory.path_join(".directory.lock")
	if not _write_owner(
		stale_lock_path,
		{
			"version": 1,
			"process_id": 99999999,
			"token": "b".repeat(32),
			"kind": "directory",
			"profile_id": null,
		}
	):
		_fail("Could not create a stale lease fixture.")
		return
	var recovered_lease: Variant = ARCHIVE_FILE_LEASE.new()
	var recovered_result: Dictionary = recovered_lease.try_acquire(profiles_directory)
	if not _require(
		recovered_result.get("ok", false),
		"An exited process lease was not reclaimed: %s" % recovered_result
	):
		return
	if not _require(recovered_lease.release(), "Recovered lease release failed."):
		return
	if not _require(
		not _contains_suffix_entry(profiles_directory, ".reclaim"),
		"Successful stale lease recovery left a reclaim directory behind."
	):
		return

	var invalid_lock_path: String = profiles_directory.path_join(".directory.lock")
	if not _write_owner(invalid_lock_path, {"unexpected": true}):
		_fail("Could not create an invalid lease fixture.")
		return
	var rejected_lease: Variant = ARCHIVE_FILE_LEASE.new()
	var rejected_result: Dictionary = rejected_lease.try_acquire(profiles_directory)
	if not _require(
		not rejected_result.get("ok", true)
			and str(rejected_result.get("error", "")).begins_with("lease_owner_")
			and DirAccess.dir_exists_absolute(invalid_lock_path),
		"An invalid lease was not rejected and preserved."
	):
		return

	DirAccess.remove_absolute(invalid_lock_path.path_join(ARCHIVE_FILE_LEASE.OWNER_FILE_NAME))
	DirAccess.remove_absolute(invalid_lock_path)
	DirAccess.remove_absolute(profiles_directory.path_join(target_name))
	if not _require(
		DirAccess.remove_absolute(profiles_directory) == OK,
		"Could not remove the isolated profiles directory."
	):
		return
	if not _require(DirAccess.remove_absolute(test_root) == OK, "Could not remove the isolated test root."):
		return

	print("Godot archive file lease smoke test passed.")
	quit(0)


func _run_worker(
		profiles_directory: String,
		profile_id: String,
		lock_kind: String,
		expected: String
) -> int:
	var output: Array = []
	var project_directory: String = ProjectSettings.globalize_path("res://")
	var arguments: PackedStringArray = [
		"--headless",
		"--path",
		project_directory,
		"--script",
		"res://tests/archive_file_lease_worker.gd",
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


func _write_owner(lock_path: String, owner: Dictionary) -> bool:
	if DirAccess.make_dir_absolute(lock_path) != OK:
		return false
	var file: FileAccess = FileAccess.open(
		lock_path.path_join(ARCHIVE_FILE_LEASE.OWNER_FILE_NAME),
		FileAccess.WRITE
	)
	if file == null:
		return false
	file.store_string(JSON.stringify(owner))
	file.flush()
	var succeeded: bool = file.get_error() == OK
	file.close()
	return succeeded


func _read_bytes(path: String) -> PackedByteArray:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var contents: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return contents


func _contains_suffix_entry(path: String, suffix: String) -> bool:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return false
	directory.set_include_hidden(true)
	if directory.list_dir_begin() != OK:
		return false
	var found: bool = false
	while true:
		var entry: String = directory.get_next()
		if entry.is_empty():
			break
		if entry.ends_with(suffix):
			found = true
			break
	directory.list_dir_end()
	return found


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
