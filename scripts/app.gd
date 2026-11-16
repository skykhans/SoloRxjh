extends Node

const REQUIRED_ENGINE_HASH: String = "ed1daf0bf001b61586d9930840f2f1394092c079"
const CONFIG_DIRECTORY: String = "res://assets/config"
const RESOURCE_MANIFEST_PATH: String = "res://assets/config/resources.json"
const CONFIG_LOADER: Script = preload("res://scripts/config_loader.gd")
const ARCHIVE_MENU: Script = preload("res://scripts/archive_menu.gd")
const TRAINING_YARD: PackedScene = preload("res://scenes/training_yard.tscn")

var app_state: AppState = AppState.LOADING
var _archive_menu: Control
var _training_yard: Node3D

enum AppState {
	LOADING,
	MAIN_MENU,
	IN_GAME,
	LOAD_ERROR,
}


func _ready() -> void:
	var arguments_result: Dictionary = parse_startup_arguments(OS.get_cmdline_user_args())
	if not arguments_result.get("ok", false):
		_fail(arguments_result.get("error", "启动参数无效。"))
		return

	var engine_error: String = validate_engine_version()
	if not engine_error.is_empty():
		_fail(engine_error)
		return

	var config_error: String = validate_runtime_config()
	if not config_error.is_empty():
		_fail(config_error)
		return

	var resource_error: String = validate_resource_manifest()
	if not resource_error.is_empty():
		_fail(resource_error)
		return

	_archive_menu = ARCHIVE_MENU.new(arguments_result["profiles_directory"]) as Control
	if _archive_menu == null:
		_fail("无法创建本地档案界面。")
		return
	_archive_menu.connect("practice_requested", _enter_practice)
	add_child(_archive_menu)
	app_state = AppState.MAIN_MENU


static func parse_startup_arguments(
		arguments: PackedStringArray,
		current_directory: String = ""
) -> Dictionary:
	if arguments.is_empty():
		return {
			"ok": true,
			"profiles_directory": "",
		}

	var save_dir_count: int = 0
	for argument: String in arguments:
		if argument == "--save-dir":
			save_dir_count += 1
	if save_dir_count > 1:
		return {
			"ok": false,
			"error": "启动参数重复：--save-dir。",
		}
	if arguments[0] != "--save-dir":
		return {
			"ok": false,
			"error": "不支持的启动参数：%s" % arguments[0],
		}
	if arguments.size() < 2:
		return {
			"ok": false,
			"error": "--save-dir 缺少存档根路径。",
		}
	if arguments.size() > 2:
		return {
			"ok": false,
			"error": "不支持的启动参数：%s" % arguments[2],
		}

	var save_root: String = arguments[1]
	if save_root.is_empty() or save_root.begins_with("--"):
		return {
			"ok": false,
			"error": "--save-dir 缺少有效的存档根路径。",
		}

	var base_directory: String = current_directory
	if base_directory.is_empty():
		var current_directory_access: DirAccess = DirAccess.open(".")
		if current_directory_access == null:
			return {
				"ok": false,
				"error": "无法解析存档路径：不能读取当前工作目录。",
			}
		base_directory = current_directory_access.get_current_dir()
	if not base_directory.is_absolute_path():
		return {
			"ok": false,
			"error": "无法解析存档路径：当前工作目录不是绝对路径。",
		}
	var absolute_root: String = (
		save_root.simplify_path()
		if save_root.is_absolute_path()
		else base_directory.path_join(save_root).simplify_path()
	)
	if not absolute_root.is_absolute_path():
		return {
			"ok": false,
			"error": "--save-dir 必须能解析为绝对路径。",
		}
	return {
		"ok": true,
		"profiles_directory": absolute_root.path_join("profiles"),
	}


static func validate_engine_version() -> String:
	var version: Dictionary = Engine.get_version_info()
	var is_required_version: bool = (
		version.get("major") == 4
		and version.get("minor") == 7
		and version.get("patch") == 2
		and version.get("status") == "stable"
		and version.get("build") == "official"
		and version.get("hash") == REQUIRED_ENGINE_HASH
	)
	if is_required_version:
		return ""

	return "需要 Godot 4.7.2 官方稳定版（%s），当前版本为 %s。" % [
		REQUIRED_ENGINE_HASH,
		version.get("string", "未知"),
	]


static func validate_runtime_config(config_dir: String = CONFIG_DIRECTORY) -> String:
	var directory: DirAccess = DirAccess.open(config_dir)
	if directory == null:
		return "缺少正式 JSON 配置目录：%s" % config_dir

	var config_paths: Array[String] = []
	_collect_json_paths(config_dir, config_paths)
	config_paths.sort()
	if config_paths.is_empty():
		return "没有正式 JSON 配置文件：%s" % config_dir

	for config_path: String in config_paths:
		var file: FileAccess = FileAccess.open(config_path, FileAccess.READ)
		if file == null:
			return "无法读取正式 JSON 配置：%s（%s）" % [
				config_path,
				error_string(FileAccess.get_open_error()),
			]

		var parsed: JSON = JSON.new()
		var parse_error: Error = parsed.parse(file.get_as_text())
		if parse_error != OK:
			return "正式 JSON 配置格式错误：%s:%d %s" % [
				config_path,
				parsed.get_error_line(),
				parsed.get_error_message(),
			]
		if not parsed.data is Dictionary:
			return "正式 JSON 配置根节点必须是对象：%s" % config_path

	return ""


static func validate_resource_manifest(manifest_path: String = RESOURCE_MANIFEST_PATH) -> String:
	return CONFIG_LOADER.validate_manifest_file(manifest_path)


func _fail(message: String) -> void:
	app_state = AppState.LOAD_ERROR
	if DisplayServer.get_name() == "headless":
		push_error(message)
		get_tree().quit(1)
		return

	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var background: ColorRect = ColorRect.new()
	background.color = Color("#101718")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(background)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(720.0, 220.0)
	center.add_child(panel)

	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	panel.add_child(content)

	var title: Label = Label.new()
	title.text = "启动失败"
	title.add_theme_color_override("font_color", Color("#f07862"))
	title.add_theme_font_size_override("font_size", 28)
	content.add_child(title)

	var detail: Label = Label.new()
	detail.text = message
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(detail)

	var close_button: Button = Button.new()
	close_button.text = "退出"
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_button.pressed.connect(_exit_failed_startup)
	content.add_child(close_button)


static func _collect_json_paths(directory_path: String, output: Array[String]) -> void:
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		return

	var file_names: PackedStringArray = directory.get_files()
	file_names.sort()
	for file_name: String in file_names:
		if file_name.get_extension().to_lower() == "json":
			output.append(directory_path.path_join(file_name))

	var child_directories: PackedStringArray = directory.get_directories()
	child_directories.sort()
	for child_directory: String in child_directories:
		_collect_json_paths(directory_path.path_join(child_directory), output)


func _enter_practice() -> void:
	if app_state != AppState.MAIN_MENU or _training_yard != null:
		return

	_training_yard = TRAINING_YARD.instantiate() as Node3D
	if _training_yard == null:
		_fail("无法创建练功场。")
		return
	_training_yard.connect("exit_requested", _return_to_archive_menu)
	_archive_menu.hide()
	add_child(_training_yard)
	app_state = AppState.IN_GAME


func _return_to_archive_menu() -> void:
	if app_state != AppState.IN_GAME or _training_yard == null:
		return
	_training_yard.queue_free()
	_training_yard = null
	_archive_menu.show()
	app_state = AppState.MAIN_MENU


func _exit_failed_startup() -> void:
	get_tree().quit(1)
