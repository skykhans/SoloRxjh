extends SceneTree


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 4 or not ClassDB.class_exists("WindowsArchiveLease"):
		push_error("Invalid lock worker arguments or missing GDExtension.")
		quit(1)
		return

	var profiles_directory: String = arguments[0]
	var profile_id: String = arguments[1]
	var lock_kind: String = arguments[2]
	var expected: String = arguments[3]
	var lease: WindowsArchiveLease = WindowsArchiveLease.new()
	var result: Dictionary
	if lock_kind == "directory":
		result = lease.try_acquire(profiles_directory)
	elif lock_kind == "profile":
		result = lease.try_acquire(profiles_directory, profile_id)
	else:
		push_error("Unknown lock kind: %s" % lock_kind)
		quit(1)
		return

	var acquired: bool = result.get("ok") == true
	var expectation_met: bool = acquired == (expected == "acquired")
	if not expectation_met:
		push_error("Lock result mismatch: %s, expected %s." % [result, expected])
		quit(1)
		return

	lease.release()
	quit(0)
