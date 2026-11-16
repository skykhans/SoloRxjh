extends Control

const ARCHIVE_REPOSITORY: Script = preload("res://scripts/archive_repository.gd")
const FONT_PATH: String = "res://assets/fonts/NotoSansCJKsc-Regular.otf"
const MODEL_PATH: String = "res://assets/models/characters/fang_chen.glb"

const COLOR_BACKGROUND: Color = Color("#101917")
const COLOR_PANEL: Color = Color("#17221f")
const COLOR_PANEL_ALT: Color = Color("#202e29")
const COLOR_TEXT: Color = Color("#e8eee9")
const COLOR_MUTED: Color = Color("#9caaa1")
const COLOR_ACCENT: Color = Color("#51b79d")
const COLOR_ERROR: Color = Color("#e78a73")
const COLOR_DIVIDER: Color = Color("#33453e")

var _repository: RefCounted
var _profile_list: VBoxContainer
var _name_input: LineEdit
var _create_button: Button
var _status: Label
var _model_pivot: Node3D
var _rename_dialog: ConfirmationDialog
var _rename_input: LineEdit
var _rename_profile_id: String = ""
var _rename_expected_name: String = ""
var _rename_expected_revision: int = 0
var _all_profiles_valid: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_repository = ARCHIVE_REPOSITORY.new()
	_build_theme()
	_build_layout()
	_refresh_profiles()


func _process(delta: float) -> void:
	if _model_pivot != null:
		_model_pivot.rotate_y(delta * 0.12)


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
	var background: ColorRect = ColorRect.new()
	background.color = COLOR_BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

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
	content.add_child(section_heading)

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
	_name_input.max_length = 32
	_name_input.placeholder_text = "档案名称"
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

	var image_column: Control = Control.new()
	image_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(image_column)
	_build_character_view(image_column)
	_build_rename_dialog()


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
	_rename_input.max_length = 32
	_rename_input.placeholder_text = "2～16个字符"
	content.add_child(_rename_input)

	_rename_dialog.get_ok_button().text = "保存"


func _build_character_view(parent: Control) -> void:
	var viewport_container: SubViewportContainer = SubViewportContainer.new()
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(viewport_container)

	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(900, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(viewport)

	var world: Node3D = Node3D.new()
	viewport.add_child(world)

	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#21302b")
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

	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0.0, 1.45, 4.8)
	camera.fov = 34.0
	camera.current = true
	camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	world.add_child(camera)

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


func _refresh_profiles() -> void:
	for child: Node in _profile_list.get_children():
		child.queue_free()

	var catalog: Dictionary = _repository.list_profiles()
	if not catalog.get("ok", false):
		_all_profiles_valid = false
		_status.text = catalog.get("error", "档案目录读取失败")
		_status.add_theme_color_override("font_color", COLOR_ERROR)
		_create_button.disabled = true
		return

	_all_profiles_valid = catalog.get("all_valid", false)
	var profiles: Array = catalog.get("profiles", [])
	if profiles.is_empty():
		var empty_state: Label = Label.new()
		empty_state.text = "尚无档案"
		empty_state.add_theme_color_override("font_color", COLOR_MUTED)
		_profile_list.add_child(empty_state)
	for profile: Dictionary in profiles:
		_profile_list.add_child(_make_profile_row(profile))

	_create_button.disabled = not catalog.get("can_create", false)
	if profiles.size() >= 3:
		_status.text = "档案数量已达上限。"
		_status.add_theme_color_override("font_color", COLOR_MUTED)
	elif not catalog.get("all_valid", false):
		_status.text = "有档案无法验证，新建已停用。"
		_status.add_theme_color_override("font_color", COLOR_ERROR)
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
	var result: Dictionary = _repository.create_profile(_name_input.text)
	if not result.get("ok", false):
		_status.text = result.get("error", "档案创建失败")
		_status.add_theme_color_override("font_color", COLOR_ERROR)
		return

	_status.text = "已创建档案：%s" % result["profile"]["profile_name"]
	_status.add_theme_color_override("font_color", COLOR_ACCENT)
	_name_input.clear()
	_refresh_profiles()


func _on_name_submitted(_submitted_text: String) -> void:
	_on_create_pressed()


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
