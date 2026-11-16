extends SceneTree

const ARCHIVE_FILE_LEASE: Script = preload("res://scripts/archive_file_lease.gd")


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 4:
		push_error("Invalid archive lease worker arguments.")
		quit(1)
		return

	var profiles_directory: String = arguments[0]
	var profile_id: String = arguments[1]
	var lock_kind: String = arguments[2]
	var expected: String = arguments[3]
	var lease: Variant = ARCHIVE_FILE_LEASE.new()
	var result: Dictionary
	if lock_kind == "directory":
		result = lease.try_acquire(profiles_directory)
	elif lock_kind == "profile":
		result = lease.try_acquire(profiles_directory, profile_id)
	else:
		push_error("Unknown lock kind: %s" % lock_kind)
		quit(1)
		return

	var acquired: bool = result.get("ok", false)
	if acquired != (expected == "acquired"):
		push_error("Lease result mismatch: %s, expected %s." % [result, expected])
		quit(1)
		return
	if acquired and not lease.release():
		push_error("Lease release failed: %s." % lease.get_last_error())
		quit(1)
		return
	quit(0)
