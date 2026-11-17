extends Control

signal practice_requested
signal quit_requested
signal session_settings_changed(settings: Dictionary)

const ARCHIVE_REPOSITORY: Script = preload("res://scripts/archive_repository.gd")
const FANG_CHEN_SWORD_VISUAL: Script = preload(
	"res://scripts/fang_chen_sword_visual.gd"
)
const FONT_PATH: String = "res://assets/fonts/NotoSansCJKsc-Regular.otf"
const MODEL_PATH: String = "res://assets/models/characters/fang_chen.glb"
const BACKGROUND_PATH: String = "res://assets/images/training_yard_backdrop.png"

const COLOR_BACKGROUND: Color = Color("#18221f")
const COLOR_PANEL: Color = Color("#1b2925")
const COLOR_PANEL_ALT: Color = Color("#293b34")
const COLOR_TEXT: Color = Color("#f0eee4")
const COLOR_MUTED: Color = Color("#c2c6b8")
const COLOR_ACCENT: Color = Color("#9fcbb0")
const COLOR_ERROR: Color = Color("#d98268")
const COLOR_DIVIDER: Color = Color("#728276")

var _repository: RefCounted
var _profile_list: VBoxContainer
var _name_input: LineEdit
var _create_button: Button
var _practice_button: Button
var _status: Label
var _capacity_label: Label
var _model_pivot: Node3D
var _rename_dialog: ConfirmationDialog
var _rename_input: LineEdit
var _rename_profile_id: String = ""
var _rename_expected_name: String = ""
var _rename_expected_revision: int = 0
var _delete_dialog: ConfirmationDialog
var _delete_summary: Label
var _delete_input: LineEdit
var _delete_profile_id: String = ""
var _delete_expected_name: String = ""
var _delete_expected_revision: int = 0
var _all_profiles_valid: bool = false
var _profiles_directory: String = ""
var _map_overlay: Control
var _settings_dialog: ConfirmationDialog
var _quit_dialog: ConfirmationDialog
var _settings_values: Dictionary = {}
var _confirmed_settings: Dictionary = {}
var _settings_controls: Dictionary = {}
var _settings_apply_generation: int = 0
var _settings_profile_id: String = ""
var _settings_profile_name: String = ""
var _settings_profile_revision: int = 0


func _init(profiles_directory: String = "") -> void:
	_profiles_directory = profiles_directory


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_repository = ARCHIVE_REPOSITORY.new(_profiles_directory)
	_build_theme()
	_build_layout()
	_refresh_profiles()


func _process(delta: float) -> void:
	if _model_pivot != null:
		_model_pivot.rotate_y(delta * 0.12)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _map_overlay != null and _map_overlay.visible:
		_map_overlay.hide()
		get_viewport().set_input_as_handled()


func _build_theme() -> void:
	var font: FontFile = load(FONT_PATH) as FontFile
	if font == null:
		push_error("无法加载正式中文字体：%s" % FONT_PATH)
		return
	var ui_theme: Theme = Theme.new()
	ui_theme.default_font = font
	ui_theme.default_font_size = 18
	theme = ui_theme


func _build_layout() -> void:
	_build_valley_background()

	var columns: HBoxContainer = HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	columns.add_theme_constant_override("separation", 0)
	add_child(columns)

	var left_column: MarginContainer = MarginContainer.new()
	left_column.custom_minimum_size = Vector2(520.0, 0.0)
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_column.add_theme_constant_override("margin_left", 64)
	left_column.add_theme_constant_override("margin_top", 46)
	left_column.add_theme_constant_override("margin_right", 44)
	left_column.add_theme_constant_override("margin_bottom", 44)
	columns.add_child(left_column)

	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	left_column.add_child(content)

	var brand: Label = Label.new()
	brand.text = "SoloRxjh"
	brand.add_theme_font_size_override("font_size", 38)
	brand.add_theme_color_override("font_color", COLOR_TEXT)
	content.add_child(brand)

	var tagline: Label = Label.new()
	tagline.text = "热血江湖 · 单机角色扮演"
	tagline.add_theme_font_size_override("font_size", 16)
	tagline.add_theme_color_override("font_color", COLOR_MUTED)
	content.add_child(tagline)

	var divider: ColorRect = ColorRect.new()
	divider.color = COLOR_DIVIDER
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	content.add_child(divider)

	var section_heading: Label = Label.new()
	section_heading.text = "本地档案"
	section_heading.add_theme_font_size_override("font_size", 24)
	section_heading.add_theme_color_override("font_color", COLOR_TEXT)
	var section_heading_row: HBoxContainer = HBoxContainer.new()
	section_heading_row.add_child(section_heading)
	_capacity_label = Label.new()
	_capacity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_capacity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_capacity_label.add_theme_font_size_override("font_size", 15)
	_capacity_label.add_theme_color_override("font_color", COLOR_MUTED)
	section_heading_row.add_child(_capacity_label)
	content.add_child(section_heading_row)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0.0, 270.0)
	content.add_child(scroll)

	_profile_list = VBoxContainer.new()
	_profile_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_profile_list)

	var create_heading: Label = Label.new()
	create_heading.text = "新建档案"
	create_heading.add_theme_font_size_override("font_size", 20)
	create_heading.add_theme_color_override("font_color", COLOR_TEXT)
	content.add_child(create_heading)

	var form: HBoxContainer = HBoxContainer.new()
	form.add_theme_constant_override("separation", 8)
	content.add_child(form)

	_name_input = LineEdit.new()
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.custom_minimum_size = Vector2(0.0, 48.0)
	_name_input.max_length = 16
	_name_input.placeholder_text = "档案名称（2～16个字符）"
	_name_input.text_submitted.connect(_on_name_submitted)
	form.add_child(_name_input)

	_create_button = _make_button("新建", true)
	_create_button.pressed.connect(_on_create_pressed)
	form.add_child(_create_button)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0.0, 42.0)
	_status.add_theme_color_override("font_color", COLOR_MUTED)
	content.add_child(_status)

	_practice_button = _make_button("进入演练场", false)
	_practice_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_practice_button.pressed.connect(_on_practice_pressed)
	content.add_child(_practice_button)
	var settings_button: Button = _make_button("本次设置", false)
	settings_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	settings_button.pressed.connect(_on_settings_pressed)
	content.add_child(settings_button)
	var quit_button: Button = _make_button("退出游戏", false)
	quit_button.name = "QuitButton"
	quit_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	quit_button.pressed.connect(_on_quit_pressed)
	content.add_child(quit_button)

	var image_column: Control = Control.new()
	image_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(image_column)
	_build_character_view(image_column)
	_build_map_overlay()
	_build_rename_dialog()
	_build_delete_dialog()
	_build_settings_dialog()
	_build_quit_dialog()


func _build_valley_background() -> void:
	var texture: Texture2D = load(BACKGROUND_PATH) as Texture2D
	if texture == null:
		push_error("无法加载正式主菜单背景：%s" % BACKGROUND_PATH)
		return
	var background: TextureRect = TextureRect.new()
	background.name = "MenuBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.texture = texture
	background.z_index = -2
	add_child(background)

	var shade: ColorRect = ColorRect.new()
	shade.name = "MenuBackgroundShade"
	shade.color = Color("#111a1680")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.z_index = -1
	add_child(shade)


func _build_map_overlay() -> void:
	_map_overlay = Control.new()
	_map_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_overlay.visible = false
	_map_overlay.z_index = 4
	add_child(_map_overlay)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color("#0b1513ef")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_overlay.add_child(backdrop)

	var map: Control = Control.new()
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.offset_left = 80.0
	map.offset_top = 72.0
	map.offset_right = -80.0
	map.offset_bottom = -72.0
	map.draw.connect(_draw_region_map.bind(map))
	_map_overlay.add_child(map)

	var heading: Label = Label.new()
	heading.text = "千竹岭"
	heading.position = Vector2(112.0, 80.0)
	heading.add_theme_font_size_override("font_size", 30)
	_map_overlay.add_child(heading)

	var description: Label = Label.new()
	description.text = "泫勃派外郊 · 竹林山径"
	description.position = Vector2(112.0, 124.0)
	description.add_theme_color_override("font_color", COLOR_MUTED)
	_map_overlay.add_child(description)

	var close_button: Button = _make_button("返回", false)
	close_button.position = Vector2(112.0, 168.0)
	close_button.pressed.connect(_map_overlay.hide)
	_map_overlay.add_child(close_button)

	var map_button: Button = _make_button("查看地图", false)
	map_button.position = Vector2(20.0, 22.0)
	map_button.z_index = 2
	map_button.pressed.connect(_map_overlay.show)
	add_child(map_button)


func _draw_region_map(map: Control) -> void:
	var size: Vector2 = map.size
	var origin: Vector2 = Vector2(size.x * 0.12, size.y * 0.2)
	var route: PackedVector2Array = PackedVector2Array([
		origin + Vector2(size.x * 0.08, size.y * 0.66),
		origin + Vector2(size.x * 0.23, size.y * 0.54),
		origin + Vector2(size.x * 0.39, size.y * 0.61),
		origin + Vector2(size.x * 0.54, size.y * 0.38),
		origin + Vector2(size.x * 0.7, size.y * 0.42),
		origin + Vector2(size.x * 0.84, size.y * 0.18),
	])
	map.draw_polyline(route, Color("#bba777"), 5.0, true)
	var font: Font = theme.default_font
	var places: Array[Dictionary] = [
		{"name": "泫勃派", "at": route[0], "color": Color("#94c8ae")},
		{"name": "竹桥", "at": route[1], "color": Color("#c4b17f")},
		{"name": "竹林营地", "at": route[2], "color": Color("#d28d67")},
		{"name": "千竹岭", "at": route[3], "color": Color("#94c8ae")},
		{"name": "巡山小径", "at": route[4], "color": Color("#c4b17f")},
		{"name": "琉璃剑宗", "at": route[5], "color": Color("#d1c18d")},
	]
	for place: Dictionary in places:
		var point: Vector2 = place["at"]
		map.draw_circle(point, 9.0, place["color"])
		map.draw_arc(point, 13.0, 0.0, TAU, 32, Color("#e5e7d8"), 1.5, true)
		map.draw_string(font, point + Vector2(17.0, 6.0), place["name"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, COLOR_TEXT)
	map.draw_string(font, Vector2(size.x * 0.67, size.y * 0.83), "溪流", HORIZONTAL_ALIGNMENT_CENTER, -1.0, 16, Color("#82b7bb"))


func _build_rename_dialog() -> void:
	_rename_dialog = ConfirmationDialog.new()
	_rename_dialog.title = "更改档案名称"
	_rename_dialog.dialog_text = "新名称将立即保存。"
	_rename_dialog.confirmed.connect(_on_rename_confirmed)
	add_child(_rename_dialog)

	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	_rename_dialog.add_child(content)

	_rename_input = LineEdit.new()
	_rename_input.custom_minimum_size = Vector2(440.0, 44.0)
	_rename_input.max_length = 16
	_rename_input.placeholder_text = "2～16个字符"
	content.add_child(_rename_input)

	_rename_dialog.get_ok_button().text = "保存"


func _build_delete_dialog() -> void:
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "永久删除档案"
	_delete_dialog.dialog_text = "此操作不可撤销。请输入完整档案名称确认。"
	_delete_dialog.confirmed.connect(_on_delete_confirmed)
	_delete_dialog.canceled.connect(_clear_delete_confirmation)
	add_child(_delete_dialog)

	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	_delete_dialog.add_child(content)

	_delete_summary = Label.new()
	_delete_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_delete_summary)

	_delete_input = LineEdit.new()
	_delete_input.custom_minimum_size = Vector2(440.0, 44.0)
	_delete_input.max_length = 32
	_delete_input.placeholder_text = "完整档案名称"
	_delete_input.text_changed.connect(_on_delete_input_changed)
	content.add_child(_delete_input)

	_delete_dialog.get_ok_button().text = "永久删除"
	_delete_dialog.get_ok_button().disabled = true


func _build_settings_dialog() -> void:
	_settings_dialog = ConfirmationDialog.new()
	_settings_dialog.title = "设置"
	_settings_dialog.dialog_text = "应用后立即作用于本次会话；之后新建的档案会保存这些设置。"
	_settings_dialog.get_ok_button().text = "应用"
	_settings_dialog.confirmed.connect(_on_settings_confirmed)
	_settings_dialog.canceled.connect(_on_settings_cancelled)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	_settings_dialog.add_child(content)

	var volume_labels: Array[String] = ["主音量", "音乐音量", "音效音量", "界面音量"]
	var volume_keys: Array[String] = [
		"master_volume", "music_volume", "sfx_volume", "ui_volume",
	]
	for index: int in range(volume_keys.size()):
		var row: HBoxContainer = HBoxContainer.new()
		content.add_child(row)
		var label: Label = Label.new()
		label.text = volume_labels[index]
		label.custom_minimum_size.x = 112.0
		row.add_child(label)
		var slider: HSlider = HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		var value_label: Label = Label.new()
		value_label.custom_minimum_size.x = 48.0
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)
		_settings_controls[volume_keys[index]] = [slider, value_label]

	_add_settings_option(
		content,
		"镜头距离",
		"camera_distance",
		[3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0],
		["3米", "4米", "5米", "6米", "7米", "8米", "9米", "10米", "11米", "12米"]
	)
	_add_settings_option(
		content,
		"窗口模式",
		"window_mode",
		["windowed", "borderless_fullscreen"],
		["窗口", "无边框全屏"]
	)
	_add_settings_option(
		content,
		"窗口分辨率",
		"window_resolution",
		[[1280, 720], [1600, 900], [1920, 1080], [2560, 1440]],
		["1280 × 720", "1600 × 900", "1920 × 1080", "2560 × 1440"]
	)
	_add_settings_option(
		content,
		"画质",
		"graphics_preset",
		["low", "medium", "high"],
		["低", "中", "高"]
	)
	_add_settings_option(
		content,
		"垂直同步",
		"vsync_enabled",
		[true, false],
		["开启", "关闭"]
	)
	add_child(_settings_dialog)


func _build_quit_dialog() -> void:
	_quit_dialog = ConfirmationDialog.new()
	_quit_dialog.name = "QuitDialog"
	_quit_dialog.title = "退出游戏"
	_quit_dialog.dialog_text = "确定退出 SoloRxjh？"
	_quit_dialog.get_ok_button().text = "退出"
	_quit_dialog.get_cancel_button().text = "继续游戏"
	_quit_dialog.confirmed.connect(_on_quit_confirmed)
	add_child(_quit_dialog)


func _on_quit_pressed() -> void:
	_quit_dialog.popup_centered()


func _on_quit_confirmed() -> void:
	quit_requested.emit()


func _add_settings_option(
	content: VBoxContainer,
	label_text: String,
	key: String,
	values: Array,
	display_values: Array
) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	content.add_child(row)
	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 112.0
	row.add_child(label)
	var option: OptionButton = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index: int in range(values.size()):
		option.add_item(str(display_values[index]))
	option.set_meta("setting_values", values)
	option.item_selected.connect(_on_settings_option_selected.bind(key))
	row.add_child(option)
	_settings_controls[key] = option


func _on_settings_pressed() -> void:
	_settings_profile_id = ""
	_settings_profile_name = ""
	_settings_profile_revision = 0
	_settings_dialog.dialog_text = "应用后立即作用于本次会话；之后新建的档案会保存这些设置。"
	if _confirmed_settings.is_empty():
		_confirmed_settings = _read_default_settings()
	_settings_values = _confirmed_settings.duplicate(true)
	_populate_settings_dialog()
	_settings_dialog.popup_centered(Vector2i(620, 580))


func _on_profile_settings_pressed(
		profile_id: String,
		profile_name: String,
		profile_revision: int,
		settings: Dictionary
) -> void:
	_settings_profile_id = profile_id
	_settings_profile_name = profile_name
	_settings_profile_revision = profile_revision
	_settings_dialog.dialog_text = "应用后立即作用于本次会话，并保存到此档案。"
	_settings_values = settings.duplicate(true)
	_populate_settings_dialog()
	_settings_dialog.popup_centered(Vector2i(620, 580))


func _read_default_settings() -> Dictionary:
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
	var settings: Dictionary = parsed.data.get("default_settings", {}).duplicate(true)
	settings["window_resolution"] = [
		int(settings["window_resolution"][0]),
		int(settings["window_resolution"][1]),
	]
	return settings


func _populate_settings_dialog() -> void:
	for key: String in _settings_controls:
		var control: Variant = _settings_controls[key]
		if key in ["master_volume", "music_volume", "sfx_volume", "ui_volume"]:
			var pair: Array = control
			var slider: HSlider = pair[0]
			var value_label: Label = pair[1]
			slider.value = float(_settings_values[key])
			value_label.text = "%d%%" % roundi(slider.value * 100.0)
			var callback: Callable = _on_volume_changed.bind(key, value_label)
			if not slider.value_changed.is_connected(callback):
				slider.value_changed.connect(callback)
		elif control is OptionButton:
			var option: OptionButton = control
			var values: Array = option.get_meta("setting_values")
			for index: int in range(values.size()):
				if values[index] == _settings_values[key]:
					option.select(index)


func _on_volume_changed(value: float, key: String, value_label: Label) -> void:
	_settings_values[key] = value
	value_label.text = "%d%%" % roundi(value * 100.0)


func _on_settings_option_selected(index: int, key: String) -> void:
	var option: OptionButton = _settings_controls[key]
	var values: Array = option.get_meta("setting_values")
	_settings_values[key] = (
		values[index].duplicate(true)
		if values[index] is Array
		else values[index]
	)


func _on_settings_confirmed() -> void:
	var candidate: Dictionary = _settings_values.duplicate(true)
	var generation_before_apply: int = _settings_apply_generation
	session_settings_changed.emit(candidate)
	if _settings_apply_generation == generation_before_apply:
		return
	if _settings_profile_id.is_empty():
		return

	var result: Dictionary = _repository.save_profile_settings(
		_settings_profile_id,
		_settings_profile_revision,
		candidate
	)
	if not result.get("ok", false):
		_status.text = "设置已应用到本次会话，但档案保存失败：%s" % result.get(
			"error",
			"未知错误"
		)
		_status.add_theme_color_override("font_color", COLOR_ERROR)
	elif not str(result.get("warning", "")).is_empty():
		_status.text = result["warning"]
		_status.add_theme_color_override("font_color", COLOR_ERROR)
	else:
		_status.text = (
			"档案设置已保存：%s" % _settings_profile_name
			if result.get("changed", false)
			else "档案设置没有变化：%s" % _settings_profile_name
		)
		_status.add_theme_color_override("font_color", COLOR_ACCENT)
	_refresh_profiles()
	_settings_profile_id = ""
	_settings_profile_name = ""
	_settings_profile_revision = 0


func _on_settings_cancelled() -> void:
	_settings_profile_id = ""
	_settings_profile_name = ""
	_settings_profile_revision = 0
	_settings_values = _confirmed_settings.duplicate(true)


func set_confirmed_session_settings(settings: Dictionary) -> void:
	_confirmed_settings = settings.duplicate(true)
	_settings_values = _confirmed_settings.duplicate(true)
	_settings_apply_generation += 1


func show_settings_error(message: String) -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", COLOR_ERROR)


func _build_character_view(parent: Control) -> void:
	var viewport_container: SubViewportContainer = SubViewportContainer.new()
	viewport_container.name = "CharacterPreviewContainer"
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(viewport_container)

	var viewport: SubViewport = SubViewport.new()
	viewport.name = "CharacterPreviewViewport"
	viewport.size = Vector2i(900, 900)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(viewport)

	var world: Node3D = Node3D.new()
	viewport.add_child(world)

	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b0c2b3")
	environment.ambient_light_energy = 0.48
	environment_node.environment = environment
	world.add_child(environment_node)

	var ground: MeshInstance3D = MeshInstance3D.new()
	var ground_mesh: PlaneMesh = PlaneMesh.new()
	ground_mesh.size = Vector2(10.0, 10.0)
	ground.mesh = ground_mesh
	ground.position.y = -0.04
	var ground_material: StandardMaterial3D = StandardMaterial3D.new()
	ground_material.albedo_color = Color("#27332d")
	ground_material.roughness = 0.92
	ground_material.metallic = 0.0
	ground.material_override = ground_material
	world.add_child(ground)

	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-32.0, -24.0, 0.0)
	key_light.light_energy = 1.35
	key_light.shadow_enabled = true
	world.add_child(key_light)

	var fill_light: OmniLight3D = OmniLight3D.new()
	fill_light.position = Vector3(-2.2, 2.4, 2.4)
	fill_light.light_color = Color("#7ebfae")
	fill_light.light_energy = 0.75
	fill_light.omni_range = 7.0
	world.add_child(fill_light)

	var model_scene: PackedScene = load(MODEL_PATH) as PackedScene
	if model_scene == null:
		push_error("无法加载档案界面角色资源：%s" % MODEL_PATH)
		return
	_model_pivot = Node3D.new()
	world.add_child(_model_pivot)
	var model: Node3D = model_scene.instantiate() as Node3D
	if model == null:
		push_error("档案界面角色资源根节点不是Node3D：%s" % MODEL_PATH)
		return
	_model_pivot.add_child(model)
	var weapon_style_result: Dictionary = FANG_CHEN_SWORD_VISUAL.apply_to_model(model)
	if not weapon_style_result.get("ok", false):
		push_error("档案界面武器样式初始化失败：%s" % weapon_style_result.get("error", "unknown"))
		return

	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0.0, 1.45, 4.8)
	camera.fov = 34.0
	camera.current = true
	world.add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)

	var caption: VBoxContainer = VBoxContainer.new()
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	caption.position = Vector2(-370.0, -94.0)
	caption.size = Vector2(330.0, 62.0)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_container.add_child(caption)

	var caption_title: Label = Label.new()
	caption_title.text = "方尘"
	caption_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption_title.add_theme_font_size_override("font_size", 22)
	caption_title.add_theme_color_override("font_color", COLOR_TEXT)
	caption.add_child(caption_title)

	var caption_detail: Label = Label.new()
	caption_detail.text = "泫勃派 · 初入江湖"
	caption_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption_detail.add_theme_font_size_override("font_size", 15)
	caption_detail.add_theme_color_override("font_color", COLOR_MUTED)
	caption.add_child(caption_detail)


func _refresh_profiles(preserve_status: bool = false) -> void:
	for child: Node in _profile_list.get_children():
		child.queue_free()

	var catalog: Dictionary = _repository.list_profiles()
	if not catalog.get("ok", false):
		_all_profiles_valid = false
		_capacity_label.text = "数量无法读取"
		if not preserve_status:
			_status.text = catalog.get("error", "档案目录读取失败")
			_status.add_theme_color_override("font_color", COLOR_ERROR)
		_create_button.disabled = true
		return

	_all_profiles_valid = catalog.get("all_valid", false)
	var profiles: Array = catalog.get("profiles", [])
	_capacity_label.text = "档案 %d / 3" % profiles.size()
	if profiles.is_empty():
		var empty_state: Label = Label.new()
		empty_state.text = "尚无档案"
		empty_state.add_theme_color_override("font_color", COLOR_MUTED)
		_profile_list.add_child(empty_state)
	for profile: Dictionary in profiles:
		_profile_list.add_child(_make_profile_row(profile))

	_create_button.disabled = not catalog.get("can_create", false)
	if not preserve_status:
		if not catalog.get("all_valid", false):
			_status.text = "有档案无法验证，新建已停用。"
			_status.add_theme_color_override("font_color", COLOR_ERROR)
		elif not catalog.get("can_create", false):
			_status.text = "档案数量已达上限。"
			_status.add_theme_color_override("font_color", COLOR_MUTED)
		elif _status.text.is_empty():
			_status.text = " "


func _make_profile_row(profile: Dictionary) -> Control:
	var row: PanelContainer = PanelContainer.new()
	row.custom_minimum_size = Vector2(0.0, 82.0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL if profile.get("valid", false) else Color("#342421")
	style.set_corner_radius_all(4)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	row.add_theme_stylebox_override("panel", style)

	var row_content: HBoxContainer = HBoxContainer.new()
	row_content.add_theme_constant_override("separation", 12)
	row.add_child(row_content)

	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 3)
	row_content.add_child(text)
	var title: Label = Label.new()
	title.text = (
		"%s  ·  %d 个角色" % [
			profile["profile_name"],
			profile["character_count"],
		]
		if profile.get("valid", false)
		else profile.get("file_name", "档案")
	)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_color_override(
		"font_color",
		COLOR_TEXT if profile.get("valid", false) else COLOR_ERROR
	)
	text.add_child(title)

	var detail: Label = Label.new()
	detail.text = (
		"修订 %d" % profile["revision"]
		if profile.get("valid", false)
		else profile.get("error", "档案不可用")
	)
	detail.add_theme_font_size_override("font_size", 14)
	detail.add_theme_color_override("font_color", COLOR_MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(detail)

	var rename_button: Button = _make_button("改名", false)
	rename_button.custom_minimum_size = Vector2(82.0, 46.0)
	rename_button.disabled = not profile.get("valid", false) or not _all_profiles_valid
	if profile.get("valid", false):
		rename_button.pressed.connect(
			_on_rename_pressed.bind(
				profile["profile_id"],
				profile["profile_name"],
				int(profile["revision"])
			)
		)
	row_content.add_child(rename_button)

	var settings_button: Button = _make_button("设置", false)
	settings_button.custom_minimum_size = Vector2(82.0, 46.0)
	settings_button.disabled = not profile.get("valid", false) or not _all_profiles_valid
	if profile.get("valid", false):
		settings_button.pressed.connect(
			_on_profile_settings_pressed.bind(
				profile["profile_id"],
				profile["profile_name"],
				int(profile["revision"]),
				profile["data"].get("settings", {}).duplicate(true)
			)
		)
	row_content.add_child(settings_button)

	var delete_button: Button = _make_button("删除", false)
	delete_button.custom_minimum_size = Vector2(82.0, 46.0)
	delete_button.disabled = not profile.get("valid", false) or not _all_profiles_valid
	if profile.get("valid", false):
		delete_button.pressed.connect(
			_on_delete_pressed.bind(
				profile["profile_id"],
				profile["profile_name"],
				int(profile["revision"]),
				int(profile["character_count"])
			)
		)
	row_content.add_child(delete_button)
	return row


func _make_button(label: String, emphasized: bool) -> Button:
	var button: Button = Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(104.0, 48.0)
	button.focus_mode = Control.FOCUS_ALL
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = COLOR_ACCENT if emphasized else COLOR_PANEL_ALT
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 16.0
	normal.content_margin_right = 16.0
	button.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#66c9ac") if emphasized else Color("#2b3d35")
	button.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#3c9a82") if emphasized else Color("#17211d")
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color("#10201b") if emphasized else COLOR_TEXT)
	return button


func _on_create_pressed() -> void:
	var settings_to_save: Variant = (
		_confirmed_settings
		if not _confirmed_settings.is_empty()
		else null
	)
	var result: Dictionary = _repository.create_profile(
		_name_input.text,
		settings_to_save
	)
	if not result.get("ok", false):
		_status.text = result.get("error", "档案创建失败")
		_status.add_theme_color_override("font_color", COLOR_ERROR)
		_refresh_profiles(true)
		return

	_status.text = "已创建档案：%s" % result["profile"]["profile_name"]
	_status.add_theme_color_override("font_color", COLOR_ACCENT)
	_name_input.clear()
	_refresh_profiles(true)


func _on_name_submitted(_submitted_text: String) -> void:
	_on_create_pressed()


func _on_practice_pressed() -> void:
	practice_requested.emit()


func _on_rename_pressed(profile_id: String, profile_name: String, revision: int) -> void:
	_rename_profile_id = profile_id
	_rename_expected_name = profile_name
	_rename_expected_revision = revision
	_rename_input.text = profile_name
	_rename_dialog.popup_centered(Vector2i(560, 190))
	_rename_input.grab_focus()
	_rename_input.select_all()


func _on_rename_confirmed() -> void:
	if _rename_profile_id.is_empty():
		return

	var result: Dictionary = _repository.rename_profile(
		_rename_profile_id,
		_rename_expected_name,
		_rename_expected_revision,
		_rename_input.text
	)
	_rename_profile_id = ""
	_rename_expected_name = ""
	_rename_expected_revision = 0
	_refresh_profiles()
	if not result.get("ok", false):
		_status.text = result.get("error", "档案改名失败")
		_status.add_theme_color_override("font_color", COLOR_ERROR)
	elif not str(result.get("warning", "")).is_empty():
		_status.text = result["warning"]
		_status.add_theme_color_override("font_color", COLOR_ERROR)
	elif result.get("changed", false):
		_status.text = "档案名称已更新：%s" % result["profile"]["profile_name"]
		_status.add_theme_color_override("font_color", COLOR_ACCENT)
	else:
		_status.text = "档案名称未变化。"
		_status.add_theme_color_override("font_color", COLOR_MUTED)


func _on_delete_pressed(
		profile_id: String,
		profile_name: String,
		revision: int,
		character_count: int
) -> void:
	_delete_profile_id = profile_id
	_delete_expected_name = profile_name
	_delete_expected_revision = revision
	_delete_summary.text = "档案：%s\nID：%s\n角色数：%d\n该档案中的角色、世界和历史将永久删除。" % [
		profile_name,
		profile_id,
		character_count,
	]
	_delete_input.clear()
	_delete_dialog.get_ok_button().disabled = true
	_delete_dialog.popup_centered(Vector2i(620, 300))
	_delete_input.grab_focus()


func _on_delete_input_changed(value: String) -> void:
	_delete_dialog.get_ok_button().disabled = (
		_delete_profile_id.is_empty()
		or value != _delete_expected_name
	)


func _on_delete_confirmed() -> void:
	if _delete_profile_id.is_empty():
		return

	var profile_id: String = _delete_profile_id
	var profile_name: String = _delete_expected_name
	var profile_revision: int = _delete_expected_revision
	var confirmation_name: String = _delete_input.text
	_clear_delete_confirmation()

	var result: Dictionary = _repository.delete_profile(
		profile_id,
		profile_name,
		profile_revision,
		confirmation_name
	)
	_refresh_profiles()
	if not result.get("ok", false):
		_status.text = result.get("error", "档案删除失败")
		_status.add_theme_color_override("font_color", COLOR_ERROR)
	elif not str(result.get("warning", "")).is_empty():
		_status.text = result["warning"]
		_status.add_theme_color_override("font_color", COLOR_ERROR)
	else:
		_status.text = "档案已永久删除：%s" % profile_name
		_status.add_theme_color_override("font_color", COLOR_ACCENT)


func _clear_delete_confirmation() -> void:
	_delete_profile_id = ""
	_delete_expected_name = ""
	_delete_expected_revision = 0
	_delete_input.clear()
	_delete_dialog.get_ok_button().disabled = true
