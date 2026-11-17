extends SceneTree

const ARCHIVE_MENU: Script = preload("res://scripts/archive_menu.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 1:
		_fail("Expected an isolated save directory.")
		return
	var profiles_directory: String = arguments[0].path_join("profiles")
	var archive_menu: Control = ARCHIVE_MENU.new(profiles_directory) as Control
	root.add_child(archive_menu)
	await process_frame

	var repository: RefCounted = archive_menu.get("_repository")
	var create_button: Button = archive_menu.get("_create_button")
	var capacity_label: Label = archive_menu.get("_capacity_label")
	var menu_background: TextureRect = archive_menu.get_node_or_null(
		"MenuBackground"
	) as TextureRect
	var character_preview: SubViewport = archive_menu.get_node_or_null(
		"CharacterPreviewViewport"
	) as SubViewport
	if character_preview == null:
		character_preview = archive_menu.find_child(
			"CharacterPreviewViewport",
			true,
			false
		) as SubViewport
	if not _require(
		repository != null
			and create_button != null
			and capacity_label != null
			and menu_background != null
			and menu_background.texture != null
			and menu_background.texture.resource_path
				== "res://assets/images/training_yard_backdrop.png"
			and menu_background.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED,
		"Archive capacity controls are missing."
	):
		return
	if not _require(character_preview != null, "Character preview viewport is missing."):
		return
	if not _require(
		character_preview.transparent_bg,
		"Character preview is not rendering with a transparent background."
	):
		return
	var preview_pivot: Node3D = archive_menu.get("_model_pivot") as Node3D
	var preview_sword: MeshInstance3D = (
		preview_pivot.find_child("Sword", true, false) as MeshInstance3D
		if preview_pivot != null
		else null
	)
	var preview_edge: StandardMaterial3D = (
		preview_sword.get_surface_override_material(3) as StandardMaterial3D
		if preview_sword != null
		else null
	)
	if not _require(
		preview_edge != null
			and preview_edge.emission_enabled
			and is_equal_approx(preview_edge.emission_energy_multiplier, 1.35),
		"Archive preview did not apply the shared character weapon style."
	):
		return
	if not _require(
		capacity_label.text == "档案 0 / 3" and not create_button.disabled,
		"Empty archive capacity was not shown correctly."
	):
		return

	var name_input: LineEdit = archive_menu.get("_name_input")
	for index: int in range(3):
		name_input.text = "档案%d" % (index + 1)
		archive_menu.call("_on_create_pressed")
		if not _require(
			str(archive_menu.get("_status").text) == "已创建档案：档案%d" % (index + 1),
			"Profile creation feedback was lost for profile %d." % (index + 1)
		):
			return
	if not _require(
		capacity_label.text == "档案 3 / 3" and create_button.disabled,
		"Full archive capacity did not disable profile creation."
	):
		return

	var rejected: Dictionary = repository.create_profile("第四档")
	if not _require(
		not rejected.get("ok", false)
			and str(rejected.get("error", "")).contains("档案数量已达上限"),
		"Repository accepted a profile beyond its capacity."
	):
		return

	var extra_candidate: String = profiles_directory.path_join("invalid.json")
	var invalid_file: FileAccess = FileAccess.open(extra_candidate, FileAccess.WRITE)
	if not _require(invalid_file != null, "Could not create invalid JSON occupancy fixture."):
		return
	invalid_file.store_string("{")
	invalid_file.close()
	archive_menu.call("_refresh_profiles")
	if not _require(
		capacity_label.text == "档案 4 / 3"
			and create_button.disabled
			and str(archive_menu.get("_status").text).contains("无法验证"),
		"Invalid JSON candidate did not occupy a profile slot or disable creation."
	):
		return

	if DirAccess.remove_absolute(extra_candidate) != OK:
		_fail("Could not remove invalid JSON occupancy fixture.")
		return
	archive_menu.call("_refresh_profiles")
	var first_profile: Dictionary = repository.list_profiles()["profiles"][0]
	archive_menu.call(
		"_on_delete_pressed",
		first_profile["profile_id"],
		first_profile["profile_name"],
		first_profile["revision"],
		first_profile["character_count"]
	)
	var delete_input: LineEdit = archive_menu.get("_delete_input")
	delete_input.text = first_profile["profile_name"]
	archive_menu.call("_on_delete_input_changed", delete_input.text)
	archive_menu.call("_on_delete_confirmed")
	if not _require(
		capacity_label.text == "档案 2 / 3"
			and not create_button.disabled
			and str(archive_menu.get("_status").text)
				== "档案已永久删除：%s" % first_profile["profile_name"],
		"Deletion did not restore capacity or preserve its success feedback."
	):
		return

	print("Archive capacity menu checks passed.")
	quit(0)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
