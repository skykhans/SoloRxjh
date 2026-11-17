extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var application: Node = MAIN_SCENE.instantiate()
	root.add_child(application)
	await process_frame
	var archive_menu: Control = application.get("_archive_menu") as Control
	if not _require(archive_menu != null, "Application did not build its archive menu."):
		return
	var settings_dialog: ConfirmationDialog = archive_menu.get("_settings_dialog")
	var controls: Dictionary = archive_menu.get("_settings_controls")
	if not _require(
		settings_dialog != null
			and controls.size() == 9
			and controls.has("master_volume")
			and controls.has("window_resolution"),
		"Settings dialog did not create all nine controls."
	):
		return
	archive_menu.call("_on_settings_pressed")
	var confirmed_settings: Dictionary = archive_menu.get("_settings_values").duplicate(true)
	var invalid_settings: Dictionary = confirmed_settings.duplicate(true)
	invalid_settings["window_resolution"] = [1366, 768]
	application.call("_apply_session_settings", invalid_settings)
	if not _require(
		application.get("_session_settings") == confirmed_settings
			and archive_menu.get("_settings_values") == confirmed_settings,
		"Failed application replaced the previously confirmed settings."
	):
		return
	var master_pair: Array = controls["master_volume"]
	var master_slider: HSlider = master_pair[0]
	master_slider.value = 0.1
	archive_menu.call("_on_volume_changed", 0.1, "master_volume", master_pair[1])
	archive_menu.call("_on_settings_cancelled")
	archive_menu.call("_on_settings_pressed")
	if not _require(
		archive_menu.get("_settings_values") == confirmed_settings,
		"Cancel did not restore the last confirmed settings draft."
	):
		return
	master_slider.value = 0.55
	archive_menu.call("_on_volume_changed", 0.55, "master_volume", master_pair[1])
	var distance_option: OptionButton = controls["camera_distance"]
	distance_option.select(6)
	archive_menu.call("_on_settings_option_selected", 6, "camera_distance")
	archive_menu.call("_on_settings_confirmed")
	var applied_master: float = AudioServer.get_bus_volume_linear(
		AudioServer.get_bus_index("Master")
	)
	if not _require(
		is_equal_approx(applied_master, 0.55),
		"Settings confirmation did not apply the session master volume: %s, draft=%s"
			% [applied_master, archive_menu.get("_settings_values")]
	):
		return
	archive_menu.emit_signal("practice_requested")
	await process_frame
	var yard: Node3D = application.get("_training_yard") as Node3D
	if not _require(
		yard != null
			and is_equal_approx(float(yard.get("_camera_distance")), 9.0),
		"Practice camera did not receive the current session distance: yard=%s distance=%s session=%s"
			% [
				yard,
				str(yard.get("_camera_distance")) if yard != null else "missing",
				application.get("_session_settings"),
			]
	):
		return
	yard.call("_request_exit")
	await process_frame
	var master_after_return: float = AudioServer.get_bus_volume_linear(
		AudioServer.get_bus_index("Master")
	)
	if not _require(
		is_equal_approx(master_after_return, 0.55),
		"Returning to the archive menu discarded the applied session settings."
	):
		return
	var name_input: LineEdit = archive_menu.get("_name_input")
	name_input.text = "设置继承"
	archive_menu.call("_on_create_pressed")
	var created_profiles: Dictionary = application.get("_archive_menu").get("_repository").list_profiles()
	var inherited_settings: Dictionary = {}
	for profile: Dictionary in created_profiles.get("profiles", []):
		if profile.get("profile_name") == "设置继承":
			inherited_settings = profile.get("data", {}).get("settings", {})
	if not _require(
		inherited_settings == application.get("_session_settings")
			and created_profiles.get("profiles", []).size() == 1,
		"Profile creation did not persist the last confirmed settings."
	):
		return

	var profile: Dictionary = created_profiles["profiles"][0]
	archive_menu.call(
		"_on_profile_settings_pressed",
		profile["profile_id"],
		profile["profile_name"],
		profile["revision"],
		inherited_settings
	)
	var valid_profile_settings: Dictionary = archive_menu.get("_settings_values").duplicate(true)
	var invalid_profile_settings: Dictionary = valid_profile_settings.duplicate(true)
	invalid_profile_settings["window_resolution"] = [1366, 768]
	archive_menu.set("_settings_values", invalid_profile_settings)
	var session_before_rejected_profile_apply: Dictionary = application.get(
		"_session_settings"
	).duplicate(true)
	archive_menu.call("_on_settings_confirmed")
	var after_rejected_profile_apply: Dictionary = archive_menu.get(
		"_repository"
	).list_profiles()
	if not _require(
		after_rejected_profile_apply.get("profiles", [])[0].get("revision") == 1
			and application.get("_session_settings") == session_before_rejected_profile_apply,
		"An invalid runtime setting changed session state or persisted to its profile."
	):
		return
	archive_menu.call(
		"_on_profile_settings_pressed",
		profile["profile_id"],
		profile["profile_name"],
		profile["revision"],
		inherited_settings
	)
	master_slider.value = 0.42
	archive_menu.call("_on_volume_changed", 0.42, "master_volume", master_pair[1])
	archive_menu.call("_on_settings_confirmed")
	var after_profile_save: Dictionary = archive_menu.get("_repository").list_profiles()
	var saved_profile: Dictionary = after_profile_save.get("profiles", [])[0]
	if not _require(
		saved_profile.get("revision") == 2
			and is_equal_approx(
				float(saved_profile.get("data", {}).get("settings", {}).get("master_volume", -1.0)),
				0.42
			)
			and is_equal_approx(
				float(application.get("_session_settings").get("master_volume", -1.0)),
				0.42
			),
		"Profile settings were not applied and saved with one revision increment."
	):
		return

	archive_menu.call(
		"_on_profile_settings_pressed",
		profile["profile_id"],
		profile["profile_name"],
		profile["revision"],
		inherited_settings
	)
	master_slider.value = 0.61
	archive_menu.call("_on_volume_changed", 0.61, "master_volume", master_pair[1])
	archive_menu.call("_on_settings_confirmed")
	var after_stale_save: Dictionary = archive_menu.get("_repository").list_profiles()
	var unchanged_profile: Dictionary = after_stale_save.get("profiles", [])[0]
	if not _require(
		unchanged_profile.get("revision") == 2
			and is_equal_approx(
				float(unchanged_profile.get("data", {}).get("settings", {}).get("master_volume", -1.0)),
				0.42
			)
			and str(archive_menu.get("_status").text).contains("档案保存失败"),
		"A stale profile settings revision was reported as successfully saved."
	):
		return
	print("Settings dialog, session application, and practice camera smoke test passed.")
	quit(0)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false
