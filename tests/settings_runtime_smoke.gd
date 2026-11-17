extends SceneTree

const SETTINGS_RUNTIME: Script = preload("res://scripts/settings_runtime.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var runtime: RefCounted = SETTINGS_RUNTIME.new()
	var defaults: Dictionary = _read_defaults()
	if not _require(not defaults.is_empty(), "Could not read settings defaults."):
		return
	var original_master_volume: float = AudioServer.get_bus_volume_linear(
		AudioServer.get_bus_index("Master")
	)
	var original_msaa: Viewport.MSAA = root.get_viewport().msaa_3d
	var viewport: Viewport = root.get_viewport()
	var original_positional_shadow_size: int = viewport.positional_shadow_atlas_size
	var original_mesh_lod_threshold: float = viewport.mesh_lod_threshold
	var original_directional_shadow_size: Variant = ProjectSettings.get_setting(
		"rendering/lights_and_shadows/directional_shadow/size"
	)
	var original_positional_project_size: Variant = ProjectSettings.get_setting(
		"rendering/lights_and_shadows/positional_shadow/atlas_size"
	)
	var original_mesh_lod_project_threshold: Variant = ProjectSettings.get_setting(
		"rendering/mesh_lod/lod_change/threshold_pixels"
	)
	var directional_light: DirectionalLight3D = DirectionalLight3D.new()
	root.add_child(directional_light)
	var original_shadow_distance: float = directional_light.directional_shadow_max_distance
	defaults["window_resolution"] = [
		int(defaults["window_resolution"][0]),
		int(defaults["window_resolution"][1]),
	]
	var invalid: Dictionary = defaults.duplicate(true)
	invalid["window_resolution"] = [1600.0, 900]
	if not _require(
		not runtime.apply(invalid, root.get_viewport()).get("ok", false),
		"A non-integer window resolution was accepted."
	):
		return

	var applied_settings: Dictionary = defaults.duplicate(true)
	var screen_size: Vector2i = DisplayServer.screen_get_size(
		DisplayServer.window_get_current_screen()
	)
	for allowed_size: Array in [[2560, 1440], [1920, 1080], [1600, 900], [1280, 720]]:
		if int(allowed_size[0]) <= screen_size.x and int(allowed_size[1]) <= screen_size.y:
			applied_settings["window_resolution"] = allowed_size.duplicate()
			break
	applied_settings["master_volume"] = 0.5
	applied_settings["music_volume"] = 0.4
	applied_settings["sfx_volume"] = 0.3
	applied_settings["ui_volume"] = 0.2
	applied_settings["graphics_preset"] = "low"
	applied_settings["vsync_enabled"] = false
	var applied: Dictionary = runtime.apply(
		applied_settings,
		root.get_viewport(),
		false
	)
	if not _require(applied.get("ok", false), "Could not apply settings: %s" % applied):
		return
	for pair: Array in [
		["Master", "master_volume"],
		["Music", "music_volume"],
		["SFX", "sfx_volume"],
		["UI", "ui_volume"],
	]:
		var bus_index: int = AudioServer.get_bus_index(pair[0])
		if not _require(
			bus_index >= 0
				and is_equal_approx(
					AudioServer.get_bus_volume_linear(bus_index),
					float(applied_settings[pair[1]])
				),
			"Audio bus volume did not match its independent setting: %s" % pair[0]
		):
			return
	if not _require(
		viewport.msaa_3d == Viewport.MSAA_DISABLED
			and viewport.positional_shadow_atlas_size == 1024
			and is_equal_approx(viewport.mesh_lod_threshold, 2.0)
			and ProjectSettings.get_setting(
				"rendering/lights_and_shadows/directional_shadow/size"
			) == 1024
			and ProjectSettings.get_setting(
				"rendering/lights_and_shadows/positional_shadow/atlas_size"
			) == 1024
			and is_equal_approx(directional_light.directional_shadow_max_distance, 30.0),
		"Low graphics preset did not apply all contract parameters."
	):
		return

	var runtime_directional_light: DirectionalLight3D = DirectionalLight3D.new()
	var runtime_light_original_distance: float = (
		runtime_directional_light.directional_shadow_max_distance
	)
	root.add_child(runtime_directional_light)
	if not _require(
		is_equal_approx(runtime_directional_light.directional_shadow_max_distance, 30.0),
		"A directional light added after settings application did not inherit the active preset."
	):
		return

	applied_settings["graphics_preset"] = "high"
	applied_settings["master_volume"] = 0.6
	if not _require(
		runtime.apply(applied_settings, root.get_viewport(), false).get("ok", false)
			and viewport.msaa_3d == Viewport.MSAA_4X
			and viewport.positional_shadow_atlas_size == 4096
			and is_equal_approx(viewport.mesh_lod_threshold, 0.5)
			and ProjectSettings.get_setting(
				"rendering/lights_and_shadows/directional_shadow/size"
			) == 4096
			and is_equal_approx(directional_light.directional_shadow_max_distance, 60.0)
			and is_equal_approx(
				runtime_directional_light.directional_shadow_max_distance,
				60.0
			)
			and is_equal_approx(
				AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Master")),
				0.6
			),
		"High graphics preset did not apply."
	):
		return
	for bus_name: String in ["Master", "Music", "SFX", "UI"]:
		AudioServer.set_bus_volume_linear(AudioServer.get_bus_index(bus_name), 0.9)
	get_root().get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	runtime.revert_applied(root.get_viewport())
	if not _require(
		viewport.msaa_3d == Viewport.MSAA_4X
			and viewport.positional_shadow_atlas_size == 4096
			and is_equal_approx(viewport.mesh_lod_threshold, 0.5)
			and is_equal_approx(directional_light.directional_shadow_max_distance, 60.0)
			and is_equal_approx(
				AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Master")),
				0.6
			),
		"Reverting an applied change did not restore the latest confirmed settings."
	):
		return
	runtime.restore(root.get_viewport())
	if not _require(
		viewport.msaa_3d == original_msaa
			and viewport.positional_shadow_atlas_size == original_positional_shadow_size
			and is_equal_approx(viewport.mesh_lod_threshold, original_mesh_lod_threshold)
			and is_equal_approx(
				runtime_directional_light.directional_shadow_max_distance,
				runtime_light_original_distance
			)
			and ProjectSettings.get_setting(
				"rendering/lights_and_shadows/directional_shadow/size"
			) == original_directional_shadow_size
			and ProjectSettings.get_setting(
				"rendering/lights_and_shadows/positional_shadow/atlas_size"
			) == original_positional_project_size
			and ProjectSettings.get_setting(
				"rendering/mesh_lod/lod_change/threshold_pixels"
			) == original_mesh_lod_project_threshold
			and is_equal_approx(
				directional_light.directional_shadow_max_distance,
				original_shadow_distance
			)
			and is_equal_approx(
				AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Master")),
				original_master_volume
			),
		"Restoring the runtime did not recover its startup environment: viewport=%s/%s, lod=%s/%s, directional_project=%s/%s, positional_project=%s/%s, mesh_project=%s/%s, lights=%s/%s, master=%s/%s"
			% [
				viewport.positional_shadow_atlas_size,
				original_positional_shadow_size,
				viewport.mesh_lod_threshold,
				original_mesh_lod_threshold,
				str(ProjectSettings.get_setting(
					"rendering/lights_and_shadows/directional_shadow/size"
				)),
				str(original_directional_shadow_size),
				str(ProjectSettings.get_setting(
					"rendering/lights_and_shadows/positional_shadow/atlas_size"
				)),
				str(original_positional_project_size),
				str(ProjectSettings.get_setting(
					"rendering/mesh_lod/lod_change/threshold_pixels"
				)),
				str(original_mesh_lod_project_threshold),
				directional_light.directional_shadow_max_distance,
				original_shadow_distance,
				AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Master")),
				original_master_volume,
			]
	):
		return
	print("Runtime settings validation, independent audio buses, display, and graphics smoke test passed.")
	quit(0)


func _read_defaults() -> Dictionary:
	var file: FileAccess = FileAccess.open(
		"res://docs/contracts/档案元数据与设置.v1.json",
		FileAccess.READ
	)
	if file == null:
		return {}
	var parsed: JSON = JSON.new()
	if parsed.parse(file.get_as_text()) != OK or not parsed.data is Dictionary:
		file.close()
		return {}
	file.close()
	return parsed.data.get("default_settings", {})


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false
