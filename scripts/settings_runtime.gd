class_name SettingsRuntime
extends RefCounted

const SETTINGS_OWNER_PATH: String = "res://docs/contracts/档案元数据与设置.v1.json"
const POSITIONAL_SHADOW_ATLAS_SETTING: String = "rendering/lights_and_shadows/positional_shadow/atlas_size"
const POSITIONAL_SHADOW_ATLAS_BITS_SETTING: String = "rendering/lights_and_shadows/positional_shadow/atlas_16_bits"
const DIRECTIONAL_SHADOW_ATLAS_SETTING: String = "rendering/lights_and_shadows/directional_shadow/size"
const DIRECTIONAL_SHADOW_ATLAS_BITS_SETTING: String = "rendering/lights_and_shadows/directional_shadow/16_bits"
const MESH_LOD_THRESHOLD_SETTING: String = "rendering/mesh_lod/lod_change/threshold_pixels"

var _original_window_mode: int = -1
var _original_window_size: Vector2i
var _original_vsync_mode: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED
var _original_msaa_3d: Viewport.MSAA
var _original_bus_volumes: Dictionary = {}
var _confirmed_window_mode: int = -1
var _confirmed_window_size: Vector2i
var _confirmed_vsync_mode: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED
var _confirmed_msaa_3d: Viewport.MSAA
var _confirmed_bus_volumes: Dictionary = {}
var _original_graphics_state: Dictionary = {}
var _confirmed_graphics_state: Dictionary = {}
var _directional_light_originals: Dictionary = {}
var _scene_tree: SceneTree
var _active_shadow_distance: float = 0.0
var _initialized: bool = false
var _has_confirmed_state: bool = false
var _last_error: String = ""

static func default_settings() -> Dictionary:
	var file: FileAccess = FileAccess.open(SETTINGS_OWNER_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: JSON = JSON.new()
	if parsed.parse(file.get_as_text()) != OK or not parsed.data is Dictionary:
		file.close()
		return {}
	file.close()
	var settings: Dictionary = parsed.data.get("default_settings", {}).duplicate(true)
	if settings.get("window_resolution") is Array:
		settings["window_resolution"] = [
			int(settings["window_resolution"][0]),
			int(settings["window_resolution"][1]),
		]
	return settings


func apply(
	settings: Dictionary,
	viewport: Viewport,
	validate_display_capability: bool = true
) -> Dictionary:
	var validation_error: String = _validate_settings(settings)
	if not validation_error.is_empty():
		return _failure(validation_error)
	if viewport == null:
		return _failure("缺少当前渲染视口。")
	var bus_error: String = _ensure_audio_buses()
	if not bus_error.is_empty():
		return _failure(bus_error)
	if not _initialized:
		_capture_original_state(viewport)

	var display_error: String = (
		_apply_display(settings, validate_display_capability)
	)
	if not display_error.is_empty():
		if _has_confirmed_state:
			_restore_confirmed_state(viewport)
		else:
			_restore_original_state(viewport)
		return _failure(display_error)
	_apply_audio(settings)
	var graphics_error: String = _apply_graphics(settings, viewport)
	if not graphics_error.is_empty():
		if _has_confirmed_state:
			_restore_confirmed_state(viewport)
		else:
			_restore_original_state(viewport)
		return _failure(graphics_error)
	_initialized = true
	_capture_confirmed_state(viewport)
	_last_error = ""
	return {"ok": true, "error": ""}


func get_last_error() -> String:
	return _last_error


func restore(viewport: Viewport) -> void:
	if not _initialized:
		return
	_restore_original_state(viewport)
	_original_window_mode = -1
	_initialized = false
	_has_confirmed_state = false
	_confirmed_bus_volumes.clear()
	_original_graphics_state.clear()
	_confirmed_graphics_state.clear()
	_directional_light_originals.clear()
	_scene_tree = null
	_active_shadow_distance = 0.0


func revert_applied(viewport: Viewport) -> void:
	if not _initialized:
		return
	if _has_confirmed_state:
		_restore_confirmed_state(viewport)
	else:
		_restore_original_state(viewport)


func _validate_settings(settings: Dictionary) -> String:
	var file: FileAccess = FileAccess.open(SETTINGS_OWNER_PATH, FileAccess.READ)
	if file == null:
		return "无法读取设置合同。"
	var parsed: JSON = JSON.new()
	var parse_error: Error = parsed.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not parsed.data is Dictionary:
		return "设置合同格式无效。"
	var defaults: Dictionary = parsed.data.get("default_settings", {})
	if defaults.is_empty() or settings.size() != defaults.size():
		return "设置必须完整包含合同规定的九个字段。"
	for key: String in defaults:
		if not settings.has(key):
			return "设置缺少字段：%s" % key
	for key: String in ["master_volume", "music_volume", "sfx_volume", "ui_volume"]:
		if not _is_number_in_range(settings[key], 0.0, 1.0):
			return "音量范围无效：%s" % key
	if not _is_number_in_range(settings["camera_distance"], 3.0, 12.0):
		return "镜头距离必须在3到12米之间。"
	if not settings["window_mode"] in ["windowed", "borderless_fullscreen"]:
		return "窗口模式无效。"
	if not settings["window_resolution"] is Array or settings["window_resolution"].size() != 2:
		return "窗口分辨率无效。"
	var resolution: Array = settings["window_resolution"]
	if typeof(resolution[0]) != TYPE_INT or typeof(resolution[1]) != TYPE_INT:
		return "窗口分辨率必须使用整数尺寸。"
	if resolution not in [[1280, 720], [1600, 900], [1920, 1080], [2560, 1440]]:
		return "窗口分辨率不在支持列表中。"
	if not settings["graphics_preset"] in ["low", "medium", "high"]:
		return "画质预设无效。"
	if typeof(settings["vsync_enabled"]) != TYPE_BOOL:
		return "垂直同步设置无效。"
	return ""


func _is_number_in_range(value: Variant, minimum: float, maximum: float) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var numeric_value: float = float(value)
	return is_finite(numeric_value) and numeric_value >= minimum and numeric_value <= maximum


func _ensure_audio_buses() -> String:
	var master_index: int = AudioServer.get_bus_index("Master")
	if master_index < 0:
		return "音频设备缺少Master总线。"
	for bus_name: String in ["Music", "SFX", "UI"]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var bus_index: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, bus_name)
		AudioServer.set_bus_send(bus_index, "Master")
	return ""


func _capture_original_state(viewport: Viewport) -> void:
	_original_window_mode = DisplayServer.window_get_mode()
	_original_window_size = DisplayServer.window_get_size()
	_original_vsync_mode = DisplayServer.window_get_vsync_mode()
	_original_msaa_3d = int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0)) as Viewport.MSAA
	_original_graphics_state = _capture_graphics_state(viewport)
	_original_bus_volumes.clear()
	for bus_name: String in ["Master", "Music", "SFX", "UI"]:
		var bus_index: int = AudioServer.get_bus_index(bus_name)
		_original_bus_volumes[bus_name] = AudioServer.get_bus_volume_linear(bus_index)
	_scene_tree = viewport.get_tree()
	if _scene_tree != null:
		if not _scene_tree.node_added.is_connected(_on_scene_node_added):
			_scene_tree.node_added.connect(_on_scene_node_added)
		for node: Node in _scene_tree.root.find_children("*", "DirectionalLight3D", true, false):
			if node is DirectionalLight3D:
				_track_directional_light(node, false)


func _capture_confirmed_state(viewport: Viewport) -> void:
	_confirmed_window_mode = DisplayServer.window_get_mode()
	_confirmed_window_size = DisplayServer.window_get_size()
	_confirmed_vsync_mode = DisplayServer.window_get_vsync_mode()
	_confirmed_msaa_3d = viewport.msaa_3d
	_confirmed_graphics_state = _capture_graphics_state(viewport)
	_confirmed_graphics_state["directional_shadow_max_distance"] = _active_shadow_distance
	_confirmed_bus_volumes.clear()
	for bus_name: String in ["Master", "Music", "SFX", "UI"]:
		var bus_index: int = AudioServer.get_bus_index(bus_name)
		_confirmed_bus_volumes[bus_name] = AudioServer.get_bus_volume_linear(bus_index)
	_has_confirmed_state = true


func _apply_display(settings: Dictionary, validate_display_capability: bool) -> String:
	var resolution: Array = settings["window_resolution"]
	if settings["window_mode"] == "windowed":
		var screen: int = DisplayServer.window_get_current_screen()
		var screen_size: Vector2i = DisplayServer.screen_get_size(screen)
		var requested_size: Vector2i = Vector2i(int(resolution[0]), int(resolution[1]))
		if validate_display_capability and (
			requested_size.x > screen_size.x or requested_size.y > screen_size.y
		):
			return "当前显示器无法容纳所选窗口分辨率。"
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(requested_size)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		var screen: int = DisplayServer.window_get_current_screen()
		var native_size: Vector2i = DisplayServer.screen_get_size(screen)
		if DisplayServer.window_get_size() != native_size:
			return "当前显示器未能应用无边框全屏尺寸。"
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if settings["vsync_enabled"] else DisplayServer.VSYNC_DISABLED
	)
	return ""


func _apply_audio(settings: Dictionary) -> void:
	AudioServer.set_bus_volume_linear(
		AudioServer.get_bus_index("Master"),
		float(settings["master_volume"])
	)
	for pair: Array in [
		["Music", "music_volume"],
		["SFX", "sfx_volume"],
		["UI", "ui_volume"],
	]:
		AudioServer.set_bus_volume_linear(
			AudioServer.get_bus_index(pair[0]),
			float(settings[pair[1]])
		)


func _apply_graphics(settings: Dictionary, viewport: Viewport) -> String:
	var contract_file: FileAccess = FileAccess.open(SETTINGS_OWNER_PATH, FileAccess.READ)
	if contract_file == null:
		return "无法读取画质预设合同。"
	var parsed: JSON = JSON.new()
	if parsed.parse(contract_file.get_as_text()) != OK or not parsed.data is Dictionary:
		contract_file.close()
		return "画质预设合同格式无效。"
	contract_file.close()
	var presets: Array = parsed.data.get("graphics_presets", [])
	for preset: Dictionary in presets:
		if preset.get("id") != settings["graphics_preset"]:
			continue
		var msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
		match preset.get("msaa_3d"):
			"2x":
				msaa = Viewport.MSAA_2X
			"4x":
				msaa = Viewport.MSAA_4X
		var graphics_state: Dictionary = _capture_graphics_state(viewport)
		graphics_state["msaa_3d"] = msaa
		graphics_state["positional_shadow_atlas_size"] = int(
			preset.get("positional_shadow_atlas_size", 0)
		)
		graphics_state["positional_shadow_project_size"] = int(
			preset.get("positional_shadow_atlas_size", 0)
		)
		graphics_state["directional_shadow_atlas_size"] = int(
			preset.get("directional_shadow_atlas_size", 0)
		)
		graphics_state["directional_shadow_max_distance"] = float(
			preset.get("directional_shadow_max_distance_m", 0.0)
		)
		graphics_state["mesh_lod_threshold"] = float(
			preset.get("mesh_lod_threshold_px", 0.0)
		)
		graphics_state["mesh_lod_project_threshold"] = float(
			preset.get("mesh_lod_threshold_px", 0.0)
		)
		if (
			graphics_state["positional_shadow_atlas_size"] <= 0
			or graphics_state["directional_shadow_atlas_size"] <= 0
			or graphics_state["directional_shadow_max_distance"] <= 0.0
			or graphics_state["mesh_lod_threshold"] <= 0.0
		):
			return "画质预设缺少有效的阴影或LOD参数。"
		_apply_graphics_state(graphics_state, viewport)
		return ""
	return "画质预设未登记：%s" % settings["graphics_preset"]


func _capture_graphics_state(viewport: Viewport) -> Dictionary:
	return {
		"msaa_3d": viewport.msaa_3d,
		"positional_shadow_atlas_size": viewport.positional_shadow_atlas_size,
		"positional_shadow_atlas_16_bits": viewport.positional_shadow_atlas_16_bits,
		"directional_shadow_atlas_size": int(
			ProjectSettings.get_setting(DIRECTIONAL_SHADOW_ATLAS_SETTING, 4096)
		),
		"directional_shadow_atlas_16_bits": bool(
			ProjectSettings.get_setting(DIRECTIONAL_SHADOW_ATLAS_BITS_SETTING, true)
		),
		"mesh_lod_threshold": viewport.mesh_lod_threshold,
		"positional_shadow_project_size": int(
			ProjectSettings.get_setting(POSITIONAL_SHADOW_ATLAS_SETTING, 4096)
		),
		"positional_shadow_project_16_bits": bool(
			ProjectSettings.get_setting(POSITIONAL_SHADOW_ATLAS_BITS_SETTING, true)
		),
		"mesh_lod_project_threshold": float(
			ProjectSettings.get_setting(MESH_LOD_THRESHOLD_SETTING, 1.0)
		),
	}


func _apply_graphics_state(state: Dictionary, viewport: Viewport) -> void:
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", state["msaa_3d"])
	viewport.msaa_3d = state["msaa_3d"]
	ProjectSettings.set_setting(
		POSITIONAL_SHADOW_ATLAS_SETTING,
		state.get("positional_shadow_project_size", state["positional_shadow_atlas_size"])
	)
	ProjectSettings.set_setting(
		POSITIONAL_SHADOW_ATLAS_BITS_SETTING,
		state.get("positional_shadow_project_16_bits", state["positional_shadow_atlas_16_bits"])
	)
	viewport.positional_shadow_atlas_size = state["positional_shadow_atlas_size"]
	viewport.positional_shadow_atlas_16_bits = state["positional_shadow_atlas_16_bits"]
	ProjectSettings.set_setting(
		DIRECTIONAL_SHADOW_ATLAS_SETTING,
		state["directional_shadow_atlas_size"]
	)
	ProjectSettings.set_setting(
		DIRECTIONAL_SHADOW_ATLAS_BITS_SETTING,
		state["directional_shadow_atlas_16_bits"]
	)
	RenderingServer.directional_shadow_atlas_set_size(
		state["directional_shadow_atlas_size"],
		state["directional_shadow_atlas_16_bits"]
	)
	ProjectSettings.set_setting(
		MESH_LOD_THRESHOLD_SETTING,
		state.get("mesh_lod_project_threshold", state["mesh_lod_threshold"])
	)
	viewport.mesh_lod_threshold = state["mesh_lod_threshold"]
	_active_shadow_distance = float(
		state.get("directional_shadow_max_distance", _active_shadow_distance)
	)
	if _scene_tree != null:
		for node: Node in _scene_tree.root.find_children("*", "DirectionalLight3D", true, false):
			if node is DirectionalLight3D:
				_track_directional_light(node, true)


func _track_directional_light(light: DirectionalLight3D, apply_active: bool) -> void:
	var light_id: int = light.get_instance_id()
	if not _directional_light_originals.has(light_id):
		_directional_light_originals[light_id] = {
			"light": weakref(light),
			"directional_shadow_max_distance": light.directional_shadow_max_distance,
		}
	if apply_active and _active_shadow_distance > 0.0:
		light.directional_shadow_max_distance = _active_shadow_distance


func _on_scene_node_added(node: Node) -> void:
	if node is DirectionalLight3D:
		_track_directional_light(node, true)


func _restore_graphics_state(state: Dictionary, viewport: Viewport) -> void:
	if state.is_empty():
		return
	_active_shadow_distance = float(state.get("directional_shadow_max_distance", 0.0))
	_apply_graphics_state(state, viewport)


func _restore_original_graphics_state(viewport: Viewport) -> void:
	if not _original_graphics_state.is_empty():
		_apply_graphics_state(_original_graphics_state, viewport)
	for light_state: Dictionary in _directional_light_originals.values():
		var light_reference: WeakRef = light_state["light"]
		var light: Variant = light_reference.get_ref()
		if is_instance_valid(light):
			light.directional_shadow_max_distance = light_state[
				"directional_shadow_max_distance"
			]
	if _scene_tree != null and _scene_tree.node_added.is_connected(_on_scene_node_added):
		_scene_tree.node_added.disconnect(_on_scene_node_added)


func _restore_original_state(viewport: Viewport = null) -> void:
	if _original_window_mode >= 0:
		DisplayServer.window_set_mode(_original_window_mode as DisplayServer.WindowMode)
		DisplayServer.window_set_size(_original_window_size)
		DisplayServer.window_set_vsync_mode(_original_vsync_mode)
	for bus_name: String in _original_bus_volumes:
		var bus_index: int = AudioServer.get_bus_index(bus_name)
		if bus_index >= 0:
			AudioServer.set_bus_volume_linear(bus_index, float(_original_bus_volumes[bus_name]))
	if viewport != null:
		_restore_original_graphics_state(viewport)


func _restore_confirmed_state(viewport: Viewport) -> void:
	DisplayServer.window_set_mode(
		_confirmed_window_mode as DisplayServer.WindowMode
	)
	DisplayServer.window_set_size(_confirmed_window_size)
	DisplayServer.window_set_vsync_mode(_confirmed_vsync_mode)
	for bus_name: String in _confirmed_bus_volumes:
		var bus_index: int = AudioServer.get_bus_index(bus_name)
		if bus_index >= 0:
			AudioServer.set_bus_volume_linear(
				bus_index,
				float(_confirmed_bus_volumes[bus_name])
			)
	if viewport != null:
		viewport.msaa_3d = _confirmed_msaa_3d
		_restore_graphics_state(_confirmed_graphics_state, viewport)


func _failure(message: String) -> Dictionary:
	_last_error = message
	return {"ok": false, "error": message}
