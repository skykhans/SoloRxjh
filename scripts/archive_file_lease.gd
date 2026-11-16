class_name ArchiveFileLease
extends RefCounted

const OWNER_FILE_NAME: String = "owner.json"
const STAGING_PREFIX: String = ".archive-lease."
const OWNER_VERSION: int = 1

var _profiles_directory: String = ""
var _lock_directory: String = ""
var _profile_id: String = ""
var _token: String = ""
var _last_error: String = ""
var _acquired: bool = false


func try_acquire(profiles_directory: String, profile_id: String = "") -> Dictionary:
	if _acquired:
		return _failure("lease_already_acquired")
	if not profile_id.is_empty() and not _is_profile_id(profile_id):
		return _failure("invalid_profile_id")

	var normalized_directory: String = profiles_directory.simplify_path()
	if not normalized_directory.is_absolute_path() or _has_link_component(normalized_directory):
		return _failure("directory_type_mismatch")
	if not DirAccess.dir_exists_absolute(normalized_directory):
		return _failure("directory_open_failed")
	if DirAccess.open(normalized_directory) == null:
		return _failure("directory_open_failed:%s" % error_string(DirAccess.get_open_error()))

	_cleanup_stale_staging_directories(normalized_directory)

	var token_bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	if token_bytes.size() != 16:
		return _failure("system_random_failed")
	var token: String = token_bytes.hex_encode()
	var process_id: int = OS.get_process_id()
	var lease_name: String = "%s%d.%s" % [STAGING_PREFIX, process_id, token]
	var staging_path: String = normalized_directory.path_join(
		"%s.pending" % lease_name
	)
	var reclaim_path: String = normalized_directory.path_join("%s.reclaim" % lease_name)
	var lock_name: String = ".directory.lock" if profile_id.is_empty() else "%s.lock" % profile_id
	var lock_path: String = normalized_directory.path_join(lock_name)

	var staging_error: Error = DirAccess.make_dir_absolute(staging_path)
	if staging_error != OK:
		return _failure("lease_staging_create_failed:%s" % error_string(staging_error))

	var owner: Dictionary = {
		"version": OWNER_VERSION,
		"process_id": process_id,
		"token": token,
		"kind": "directory" if profile_id.is_empty() else "profile",
		"profile_id": null if profile_id.is_empty() else profile_id,
	}
	var owner_error: String = _write_owner(staging_path, owner)
	if not owner_error.is_empty():
		_remove_staging_directory(staging_path)
		return _failure(owner_error)

	var publish_error: Error = DirAccess.rename_absolute(staging_path, lock_path)
	if publish_error != OK:
		if not _path_exists(lock_path):
			_remove_staging_directory(staging_path)
			return _failure("lease_publish_failed:%s" % error_string(publish_error))
		var reclaim_result: Dictionary = _reclaim_stale_lock(
			lock_path,
			profile_id,
			reclaim_path
		)
		if not reclaim_result.get("ok", false):
			_remove_staging_directory(staging_path)
			return _failure(str(reclaim_result.get("error", "lease_in_use")))
		publish_error = DirAccess.rename_absolute(staging_path, lock_path)
		if publish_error != OK:
			_remove_staging_directory(staging_path)
			return _failure("lease_publish_failed:%s" % error_string(publish_error))

	_profiles_directory = normalized_directory
	_lock_directory = lock_path
	_profile_id = profile_id
	_token = token
	_last_error = ""
	_acquired = true
	return {
		"ok": true,
		"error": "",
	}


func enumerate_profile_candidates(profiles_directory: String) -> Dictionary:
	if not _profile_id.is_empty():
		return _failure("directory_lease_required")
	var lease_error: String = _validate_lease_directory(profiles_directory)
	if not lease_error.is_empty():
		return _failure(lease_error)

	var directory: DirAccess = DirAccess.open(_profiles_directory)
	if directory == null:
		return _failure("directory_enumeration_failed:%s" % error_string(DirAccess.get_open_error()))
	directory.set_include_hidden(true)
	var begin_error: Error = directory.list_dir_begin()
	if begin_error != OK:
		return _failure("directory_enumeration_failed:%s" % error_string(begin_error))

	var entries: Array[Dictionary] = []
	while true:
		var file_name: String = directory.get_next()
		if file_name.is_empty():
			break
		if file_name == "." or file_name == ".." or not file_name.to_lower().ends_with(".json"):
			continue
		entries.push_back({
			"name": file_name,
			"is_directory": directory.current_is_dir(),
			"is_reparse_point": directory.is_link(file_name),
		})
	directory.list_dir_end()
	entries.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return str(left["name"]) < str(right["name"])
	)
	return {
		"ok": true,
		"error": "",
		"entries": entries,
	}


func read_profile_candidate(profiles_directory: String, file_name: String) -> Dictionary:
	if not _profile_id.is_empty():
		return _failure("directory_lease_required")
	if not _is_candidate_name(file_name):
		return _failure("invalid_file_name")
	var lease_error: String = _validate_lease_directory(profiles_directory)
	if not lease_error.is_empty():
		return _failure(lease_error)

	var directory: DirAccess = DirAccess.open(_profiles_directory)
	if directory == null:
		return _failure("candidate_open_failed:%s" % error_string(DirAccess.get_open_error()))
	if directory.is_link(file_name) or directory.dir_exists(file_name):
		return _failure("candidate_type_mismatch")

	var file_path: String = _profiles_directory.path_join(file_name)
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return _failure("candidate_open_failed:%s" % error_string(FileAccess.get_open_error()))
	var file_length: int = file.get_length()
	if file_length < 0:
		file.close()
		return _failure("candidate_size_failed")
	var contents: PackedByteArray = file.get_buffer(file_length)
	var read_error: Error = file.get_error()
	file.close()
	if contents.size() != file_length or read_error != OK:
		return _failure("candidate_read_failed:%s" % error_string(read_error))
	return {
		"ok": true,
		"error": "",
		"bytes": contents,
	}


func publish_bytes(
		profiles_directory: String,
		temporary_name: String,
		target_name: String,
		contents: PackedByteArray,
		replace: bool
) -> Dictionary:
	if not _profile_id.is_empty():
		return _failure("directory_lease_required")
	if not _is_leaf_name(temporary_name) or not _is_leaf_name(target_name):
		return _failure("invalid_file_name")
	var lease_error: String = _validate_lease_directory(profiles_directory)
	if not lease_error.is_empty():
		return _failure(lease_error)

	var directory: DirAccess = DirAccess.open(_profiles_directory)
	if directory == null:
		return _failure("publish_directory_open_failed:%s" % error_string(DirAccess.get_open_error()))

	var temporary_path: String = _profiles_directory.path_join(temporary_name)
	if _path_exists(temporary_path):
		return _failure("temporary_file_exists")

	var target_path: String = _profiles_directory.path_join(target_name)
	if directory.is_link(target_name) or directory.dir_exists(target_name):
		return _failure("publish_target_type_mismatch")
	var target_exists: bool = directory.file_exists(target_name)
	if replace and not target_exists:
		return _failure("publish_target_missing")
	if not replace and target_exists:
		return _failure("publish_target_exists")

	var temporary_file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if temporary_file == null:
		return _failure("temporary_file_create_failed:%s" % error_string(FileAccess.get_open_error()))
	temporary_file.store_buffer(contents)
	temporary_file.flush()
	var write_error: Error = temporary_file.get_error()
	temporary_file.close()
	if write_error != OK:
		_remove_owned_temporary(temporary_path)
		return _failure("temporary_file_flush_failed:%s" % error_string(write_error))

	if directory.is_link(target_name) or directory.dir_exists(target_name):
		_remove_owned_temporary(temporary_path)
		return _failure("publish_target_type_mismatch")
	target_exists = directory.file_exists(target_name)
	if replace and not target_exists:
		_remove_owned_temporary(temporary_path)
		return _failure("publish_target_missing")
	if not replace and target_exists:
		_remove_owned_temporary(temporary_path)
		return _failure("publish_target_exists")

	var rename_error: Error = DirAccess.rename_absolute(temporary_path, target_path)
	if rename_error != OK:
		_remove_owned_temporary(temporary_path)
		return _failure("atomic_publish_failed:%s" % error_string(rename_error))
	return {
		"ok": true,
		"error": "",
	}


func release() -> bool:
	if not _acquired:
		return true
	var owner_result: Dictionary = _read_owner(_lock_directory, _profile_id)
	if not owner_result.get("ok", false):
		_last_error = str(owner_result.get("error", "lease_owner_invalid"))
		return false
	var owner: Dictionary = owner_result["owner"]
	if int(owner["process_id"]) != OS.get_process_id() or owner["token"] != _token:
		_last_error = "lease_owner_mismatch"
		return false
	var cleanup_result: Dictionary = _remove_lock_directory(_lock_directory)
	if not cleanup_result.get("ok", false):
		_last_error = str(cleanup_result.get("error", "lease_release_failed"))
		return false
	_reset_lease()
	return true


func is_acquired() -> bool:
	return _acquired


func get_last_error() -> String:
	return _last_error


func _validate_lease_directory(profiles_directory: String) -> String:
	if not _acquired:
		return "lease_not_acquired"
	var requested_directory: String = profiles_directory.simplify_path()
	if requested_directory.nocasecmp_to(_profiles_directory) != 0:
		return "lease_directory_mismatch"
	if _has_link_component(requested_directory):
		return "directory_type_mismatch"
	var owner_result: Dictionary = _read_owner(_lock_directory, _profile_id)
	if not owner_result.get("ok", false):
		return str(owner_result.get("error", "lease_owner_invalid"))
	var owner: Dictionary = owner_result["owner"]
	if int(owner["process_id"]) != OS.get_process_id() or owner["token"] != _token:
		return "lease_owner_mismatch"
	return ""


func _reclaim_stale_lock(
		lock_path: String,
		profile_id: String,
		reclaim_path: String
) -> Dictionary:
	if _entry_is_link(lock_path):
		return _failure("lease_path_is_link")
	if not DirAccess.dir_exists_absolute(lock_path):
		return _failure("lease_path_type_mismatch")
	var owner_result: Dictionary = _read_owner(lock_path, profile_id)
	if not owner_result.get("ok", false):
		return owner_result
	var owner: Dictionary = owner_result["owner"]
	var process_id: int = int(owner["process_id"])
	var process_result: Dictionary = _query_process_running(process_id)
	if not process_result.get("ok", false):
		return process_result
	if process_result["running"]:
		return _failure("profile_in_use")
	if _path_exists(reclaim_path):
		return _failure("lease_reclaim_target_exists")
	var move_error: Error = DirAccess.rename_absolute(lock_path, reclaim_path)
	if move_error != OK:
		return _failure("lease_reclaim_race")
	var moved_owner_result: Dictionary = _read_owner(reclaim_path, profile_id)
	if not moved_owner_result.get("ok", false):
		var invalid_owner_restore_error: Error = DirAccess.rename_absolute(reclaim_path, lock_path)
		if invalid_owner_restore_error != OK:
			return _failure(
				"lease_reclaim_restore_failed:%s" % error_string(invalid_owner_restore_error)
			)
		return _failure(str(moved_owner_result.get("error", "lease_reclaim_owner_invalid")))
	var moved_owner: Dictionary = moved_owner_result["owner"]
	if (
		int(moved_owner["process_id"]) != process_id
		or moved_owner["token"] != owner["token"]
	):
		var identity_restore_error: Error = DirAccess.rename_absolute(reclaim_path, lock_path)
		if identity_restore_error != OK:
			return _failure("lease_reclaim_restore_failed:%s" % error_string(identity_restore_error))
		return _failure("lease_reclaim_identity_changed")
	var cleanup_result: Dictionary = _remove_lock_directory(reclaim_path)
	if not cleanup_result.get("ok", false):
		if not _path_exists(lock_path):
			var cleanup_restore_error: Error = DirAccess.rename_absolute(reclaim_path, lock_path)
			if cleanup_restore_error != OK:
				return _failure("lease_reclaim_restore_failed:%s" % error_string(cleanup_restore_error))
		return cleanup_result
	return {
		"ok": true,
	}


func _read_owner(lock_path: String, profile_id: String) -> Dictionary:
	if _entry_is_link(lock_path):
		return _failure("lease_path_is_link")
	if not DirAccess.dir_exists_absolute(lock_path):
		return _failure("lease_path_type_mismatch")
	var lock_directory: DirAccess = DirAccess.open(lock_path)
	if lock_directory == null:
		return _failure("lease_directory_open_failed")
	if lock_directory.is_link(OWNER_FILE_NAME):
		return _failure("lease_owner_is_link")
	var owner_path: String = lock_path.path_join(OWNER_FILE_NAME)
	var file: FileAccess = FileAccess.open(owner_path, FileAccess.READ)
	if file == null:
		return _failure("lease_owner_open_failed:%s" % error_string(FileAccess.get_open_error()))
	var json: JSON = JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return _failure("lease_owner_parse_failed")
	if not json.data is Dictionary:
		return _failure("lease_owner_not_object")
	var owner: Dictionary = json.data
	if owner.size() != 5:
		return _failure("lease_owner_key_count")
	for key: String in ["version", "process_id", "token", "kind", "profile_id"]:
		if not owner.has(key):
			return _failure("lease_owner_key_missing:%s" % key)
	if not _is_integer_value(owner["version"]) or int(owner["version"]) != OWNER_VERSION:
		return _failure("lease_owner_version_invalid")
	if not _is_integer_value(owner["process_id"]) or int(owner["process_id"]) <= 0:
		return _failure("lease_owner_process_invalid")
	if typeof(owner["token"]) != TYPE_STRING or not _is_token(owner["token"]):
		return _failure("lease_owner_token_invalid")
	var expected_kind: String = "directory" if profile_id.is_empty() else "profile"
	if typeof(owner["kind"]) != TYPE_STRING or owner["kind"] != expected_kind:
		return _failure("lease_owner_kind_invalid")
	var expected_profile_id: Variant = null if profile_id.is_empty() else profile_id
	if owner["profile_id"] != expected_profile_id:
		return _failure("lease_owner_profile_invalid")
	var entries_result: Dictionary = _list_directory_entries(lock_path)
	if not entries_result.get("ok", false):
		return entries_result
	if entries_result["entries"] != [OWNER_FILE_NAME]:
		return _failure("lease_directory_contents_invalid")
	return {
		"ok": true,
		"owner": owner,
	}


func _write_owner(directory_path: String, owner: Dictionary) -> String:
	var owner_path: String = directory_path.path_join(OWNER_FILE_NAME)
	var file: FileAccess = FileAccess.open(owner_path, FileAccess.WRITE)
	if file == null:
		return "lease_owner_create_failed:%s" % error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(owner) + "\n")
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return "lease_owner_flush_failed:%s" % error_string(write_error)
	return ""


func _remove_lock_directory(lock_path: String) -> Dictionary:
	var entries_result: Dictionary = _list_directory_entries(lock_path)
	if not entries_result.get("ok", false):
		return entries_result
	if entries_result["entries"] != [OWNER_FILE_NAME]:
		return _failure("lease_directory_not_empty")
	var owner_path: String = lock_path.path_join(OWNER_FILE_NAME)
	if _entry_is_link(owner_path):
		return _failure("lease_owner_is_link")
	var owner_remove_error: Error = DirAccess.remove_absolute(owner_path)
	if owner_remove_error != OK:
		return _failure("lease_owner_remove_failed:%s" % error_string(owner_remove_error))
	var directory_remove_error: Error = DirAccess.remove_absolute(lock_path)
	if directory_remove_error != OK:
		return _failure("lease_directory_remove_failed:%s" % error_string(directory_remove_error))
	return {
		"ok": true,
	}


func _cleanup_stale_staging_directories(profiles_directory: String) -> void:
	var listing: Dictionary = _list_directory_entries(profiles_directory)
	if not listing.get("ok", false):
		return
	for entry: String in listing["entries"]:
		var identity: Dictionary = _parse_staging_name(entry)
		if not identity.get("ok", false):
			continue
		var process_result: Dictionary = _query_process_running(identity["process_id"])
		if not process_result.get("ok", false) or process_result["running"]:
			continue
		var staging_path: String = profiles_directory.path_join(entry)
		if _entry_is_link(staging_path):
			continue
		var owner_path: String = staging_path.path_join(OWNER_FILE_NAME)
		if FileAccess.file_exists(owner_path):
			var owner_result: Dictionary = _read_staging_owner(staging_path, identity)
			if not owner_result.get("ok", false):
				continue
		_remove_staging_directory(staging_path)


func _read_staging_owner(staging_path: String, identity: Dictionary) -> Dictionary:
	var directory: DirAccess = DirAccess.open(staging_path)
	if directory == null or directory.is_link(OWNER_FILE_NAME):
		return _failure("lease_owner_invalid")
	var file: FileAccess = FileAccess.open(staging_path.path_join(OWNER_FILE_NAME), FileAccess.READ)
	if file == null:
		return _failure("lease_owner_invalid")
	var json: JSON = JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary:
		return _failure("lease_owner_invalid")
	var owner: Dictionary = json.data
	if (
		not _is_integer_value(owner.get("process_id"))
		or int(owner["process_id"]) != identity["process_id"]
		or owner.get("token") != identity["token"]
		or not _is_integer_value(owner.get("version"))
		or int(owner["version"]) != OWNER_VERSION
	):
		return _failure("lease_owner_invalid")
	var entries_result: Dictionary = _list_directory_entries(staging_path)
	if not entries_result.get("ok", false):
		return entries_result
	if entries_result["entries"] != [OWNER_FILE_NAME]:
		return _failure("lease_directory_not_empty")
	return {
		"ok": true,
	}


func _remove_staging_directory(staging_path: String) -> void:
	if _entry_is_link(staging_path):
		return
	if not DirAccess.dir_exists_absolute(staging_path):
		return
	var owner_path: String = staging_path.path_join(OWNER_FILE_NAME)
	if FileAccess.file_exists(owner_path) and not _entry_is_link(owner_path):
		DirAccess.remove_absolute(owner_path)
	DirAccess.remove_absolute(staging_path)


func _remove_owned_temporary(temporary_path: String) -> void:
	if _entry_is_link(temporary_path):
		return
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(temporary_path)


func _list_directory_entries(path: String) -> Dictionary:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return _failure("directory_enumeration_failed:%s" % error_string(DirAccess.get_open_error()))
	directory.set_include_hidden(true)
	var begin_error: Error = directory.list_dir_begin()
	if begin_error != OK:
		return _failure("directory_enumeration_failed:%s" % error_string(begin_error))
	var entries: Array[String] = []
	while true:
		var entry: String = directory.get_next()
		if entry.is_empty():
			break
		if entry != "." and entry != "..":
			entries.push_back(entry)
	directory.list_dir_end()
	entries.sort()
	return {
		"ok": true,
		"entries": entries,
	}


func _parse_staging_name(file_name: String) -> Dictionary:
	var parts: PackedStringArray = file_name.split(".")
	if (
		parts.size() != 5
		or parts[0] != ""
		or parts[1] != "archive-lease"
		or parts[4] != "pending"
		or not _is_decimal(parts[2])
		or not _is_token(parts[3])
	):
		return _failure("invalid_staging_name")
	var process_id: int = parts[2].to_int()
	if process_id <= 0 or str(process_id) != parts[2]:
		return _failure("invalid_staging_name")
	return {
		"ok": true,
		"process_id": process_id,
		"token": parts[3],
	}


func _query_process_running(process_id: int) -> Dictionary:
	if OS.get_name() != "Windows":
		return _failure("process_status_unavailable")
	var system_root: String = OS.get_environment("SystemRoot")
	if system_root.is_empty():
		return _failure("process_status_unavailable")
	var tasklist_path: String = system_root.path_join("System32").path_join("tasklist.exe")
	if not FileAccess.file_exists(tasklist_path):
		return _failure("process_status_unavailable")
	var output: Array = []
	var exit_code: int = OS.execute(
		tasklist_path,
		PackedStringArray([
			"/FI",
			"PID eq %d" % process_id,
			"/FO",
			"CSV",
			"/NH",
		]),
		output,
		true
	)
	if exit_code != 0:
		return _failure("process_status_failed")
	for output_line: Variant in output:
		for line: String in str(output_line).split("\n"):
			var trimmed_line: String = line.strip_edges()
			if not trimmed_line.begins_with("\""):
				continue
			var fields: PackedStringArray = trimmed_line.split("\",\"")
			if fields.size() < 2 or not _is_decimal(fields[1]):
				continue
			if int(fields[1]) == process_id:
				return {
					"ok": true,
					"running": true,
				}
	return {
		"ok": true,
		"running": false,
	}


func _entry_is_link(path: String) -> bool:
	var parent_path: String = path.get_base_dir()
	var parent: DirAccess = DirAccess.open(parent_path)
	return parent != null and parent.is_link(path.get_file())


func _path_exists(path: String) -> bool:
	return _entry_is_link(path) or FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)


func _has_link_component(path: String) -> bool:
	var current: String = path.simplify_path()
	while not current.get_file().is_empty():
		var parent_path: String = current.get_base_dir()
		if parent_path.is_empty() or parent_path == current:
			break
		var parent: DirAccess = DirAccess.open(parent_path)
		if parent != null and parent.is_link(current.get_file()):
			return true
		current = parent_path
	return false


func _is_decimal(value: String) -> bool:
	if value.is_empty():
		return false
	for index: int in range(value.length()):
		var codepoint: int = value.unicode_at(index)
		if codepoint < 0x30 or codepoint > 0x39:
			return false
	return true


func _is_integer_value(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var numeric_value: float = float(value)
	return is_finite(numeric_value) and floor(numeric_value) == numeric_value


func _is_token(value: String) -> bool:
	if value.length() != 32:
		return false
	for index: int in range(value.length()):
		var codepoint: int = value.unicode_at(index)
		if not (codepoint in range(0x30, 0x3A) or codepoint in range(0x61, 0x67)):
			return false
	return true


func _is_profile_id(profile_id: String) -> bool:
	if profile_id.length() != 40 or not profile_id.begins_with("profile_"):
		return false
	for index: int in range(8, profile_id.length()):
		var codepoint: int = profile_id.unicode_at(index)
		if not (codepoint in range(0x30, 0x3A) or codepoint in range(0x61, 0x67)):
			return false
	return true


func _is_leaf_name(file_name: String) -> bool:
	if file_name.is_empty() or file_name == "." or file_name == "..":
		return false
	if file_name.ends_with(".") or file_name.ends_with(" "):
		return false
	for index: int in range(file_name.length()):
		var codepoint: int = file_name.unicode_at(index)
		if (
			codepoint < 0x20
			or codepoint in [0x2F, 0x5C, 0x3A, 0x3C, 0x3E, 0x22, 0x7C, 0x3F, 0x2A]
		):
			return false
	return true


func _is_candidate_name(file_name: String) -> bool:
	if file_name.is_empty() or file_name == "." or file_name == "..":
		return false
	if file_name.ends_with(".") or file_name.ends_with(" "):
		return false
	for index: int in range(file_name.length()):
		var codepoint: int = file_name.unicode_at(index)
		if codepoint < 0x20 or codepoint in [0x2F, 0x5C, 0x3A]:
			return false
	return true


func _reset_lease() -> void:
	_profiles_directory = ""
	_lock_directory = ""
	_profile_id = ""
	_token = ""
	_acquired = false
	_last_error = ""


func _failure(error: String) -> Dictionary:
	_last_error = error
	return {
		"ok": false,
		"error": error,
	}
