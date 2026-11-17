extends SceneTree

const ARCHIVE_MENU: Script = preload("res://scripts/archive_menu.gd")

var _quit_requests: int = 0


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 1:
		_fail("Expected an isolated profiles directory argument.")
		return
	var menu: Control = ARCHIVE_MENU.new(arguments[0]) as Control
	if not _require(menu != null, "Archive menu did not instantiate."):
		return
	root.add_child(menu)
	menu.quit_requested.connect(_on_quit_requested)
	await process_frame

	var quit_button: Button = menu.find_child("QuitButton", true, false) as Button
	var quit_dialog: ConfirmationDialog = menu.get_node_or_null("QuitDialog") as ConfirmationDialog
	if not _require(
		quit_button != null and quit_dialog != null,
		"Archive menu is missing its quit control or confirmation."
	):
		return
	quit_button.pressed.emit()
	await process_frame
	if not _require(quit_dialog.visible, "Quit confirmation did not open."):
		return
	quit_dialog.get_cancel_button().pressed.emit()
	await process_frame
	if not _require(
		not quit_dialog.visible and _quit_requests == 0,
		"Canceling quit emitted an exit request."
	):
		return

	quit_button.pressed.emit()
	await process_frame
	quit_dialog.get_ok_button().pressed.emit()
	await process_frame
	if not _require(_quit_requests == 1, "Confirming quit did not emit exactly once."):
		return

	print("Archive menu quit confirmation smoke test passed.")
	quit(0)


func _on_quit_requested() -> void:
	_quit_requests += 1


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
