extends Control

signal exit_requested
signal settings_requested

const MODEL_PATH := "res://assets/models/characters/fang_chen.glb"
const BACKGROUND_PATH := "res://assets/images/qianzhu_valley_menu.png"
const FONT_PATH := "res://assets/fonts/NotoSansCJKsc-Regular.otf"
const VISUAL_STYLE: Script = preload("res://scripts/fang_chen_visual_style.gd")

const TEXT := Color("#f0eee4")
const MUTED := Color("#bbc7bd")
const ACCENT := Color("#a9d7bd")
const PANEL := Color("#14211fdc")

var _overlay: PanelContainer
var _overlay_title: Label
var _overlay_body: RichTextLabel
var _model_pivot: Node3D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var font := load(FONT_PATH) as FontFile
	if font == null:
		push_error("无法加载正式中文字体：%s" % FONT_PATH)
		return
	var ui_theme := Theme.new()
	ui_theme.default_font = font
	ui_theme.default_font_size = 16
	theme = ui_theme
	_build_scene()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("close_or_pause"):
		if _overlay != null and _overlay.visible:
			_overlay.hide()
		else:
			_open_panel("暂停", "返回档案或退出游戏。")
		get_viewport().set_input_as_handled()


func _build_scene() -> void:
	var background := TextureRect.new()
	background.name = "XuanboBackground"
	background.texture = load(BACKGROUND_PATH)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var shade := ColorRect.new()
	shade.color = Color("#07110d55")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_build_character()
	_build_hud()
	_build_overlay()


func _build_character() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var model_scene := load(MODEL_PATH) as PackedScene
	if model_scene == null:
		push_error("无法加载方尘人物模型。")
		return
	var model := model_scene.instantiate() as Node3D
	if model == null:
		push_error("方尘人物模型根节点无效。")
		return
	var style: Dictionary = VISUAL_STYLE.apply_to_model(model)
	if not style.get("ok", false):
		push_error("人物材质初始化失败：%s" % style.get("error", "unknown"))
	_model_pivot = Node3D.new()
	_model_pivot.name = "Character"
	_model_pivot.add_child(model)

	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "CharacterPortrait"
	viewport_container.set_anchors_preset(Control.PRESET_CENTER)
	viewport_container.offset_left = -330.0
	viewport_container.offset_top = -390.0
	viewport_container.offset_right = 330.0
	viewport_container.offset_bottom = 390.0
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_container.z_index = 1
	add_child(viewport_container)
	var viewport := SubViewport.new()
	viewport.name = "CharacterViewport"
	viewport.size = Vector2i(660, 780)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(viewport)
	var camera := Camera3D.new()
	camera.position = Vector3(2.6, 2.3, 5.3)
	camera.fov = 34.0
	viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-34.0, -28.0, 0.0)
	light.light_energy = 1.5
	viewport.add_child(light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.0, 2.0, 2.0)
	fill.light_color = Color("#8de3c8")
	fill.light_energy = 1.1
	fill.omni_range = 8.0
	viewport.add_child(fill)
	viewport.add_child(_model_pivot)
	var animation := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation != null and animation.has_animation(&"Idle"):
		animation.play(&"Idle")


func _build_hud() -> void:
	var top_left := _panel(Vector2(24, 22), Vector2(310, 86))
	top_left.name = "PlayerStatus"
	var status := VBoxContainer.new()
	status.add_theme_constant_override("separation", 5)
	top_left.add_child(status)
	status.add_child(_label("角色尚未载入", 20, TEXT))
	status.add_child(_label("泫勃派  |  安全城区", 15, ACCENT))

	var location := _label("泫勃派", 26, TEXT)
	location.set_anchors_preset(Control.PRESET_CENTER_TOP)
	location.position = Vector2(-70, 22)
	location.add_theme_color_override("font_shadow_color", Color("#07110d"))
	location.add_theme_constant_override("shadow_offset_x", 2)
	location.add_theme_constant_override("shadow_offset_y", 2)
	location.z_index = 3
	add_child(location)
	var subtitle := _label("青石长街 · 城区安全区", 15, MUTED)
	subtitle.set_anchors_preset(Control.PRESET_CENTER_TOP)
	subtitle.position = Vector2(-92, 58)
	subtitle.z_index = 3
	add_child(subtitle)

	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-216, 22)
	right.custom_minimum_size.x = 192
	right.add_theme_constant_override("separation", 7)
	right.z_index = 3
	add_child(right)
	var map_button := _button("世界地图", "world_map")
	map_button.custom_minimum_size.y = 44
	right.add_child(map_button)
	right.add_child(_label("泫勃派 · 新手起点", 14, MUTED))

	var quick_menu := HBoxContainer.new()
	quick_menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	quick_menu.position = Vector2(24, 158)
	quick_menu.add_theme_constant_override("separation", 6)
	quick_menu.z_index = 3
	add_child(quick_menu)
	for item in [["背包", "inventory"], ["角色", "character"], ["武学", "skills"], ["任务", "quests"]]:
		quick_menu.add_child(_button(item[0], item[1]))

	var shop_menu := VBoxContainer.new()
	shop_menu.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	shop_menu.position = Vector2(-198, -45)
	shop_menu.add_theme_constant_override("separation", 8)
	shop_menu.z_index = 3
	add_child(shop_menu)
	shop_menu.add_child(_button("补给商", "official_shop"))
	shop_menu.add_child(_button("交易市场", "market"))
	shop_menu.add_child(_button("铁匠铺", "blacksmith"))

	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.position = Vector2(-260, -80)
	bottom.custom_minimum_size = Vector2(520, 58)
	bottom.add_theme_stylebox_override("panel", _panel_style())
	bottom.z_index = 3
	add_child(bottom)
	var hotbar := HBoxContainer.new()
	hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	hotbar.add_theme_constant_override("separation", 12)
	bottom.add_child(hotbar)
	for key in ["1  药品", "2  内力", "Q  武学", "R  武学", "J  攻击", "F  交互"]:
		var slot := _label(key, 14, TEXT)
		slot.custom_minimum_size.x = 70
		hotbar.add_child(slot)

	var chat := _panel(Vector2(24, -150), Vector2(430, 122))
	chat.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat.name = "ChatPanel"
	var chat_text := _label("泫勃派城区\n角色、任务、商店与交易服务尚未接入。", 14, MUTED)
	chat_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chat.add_child(chat_text)

	var footer := HBoxContainer.new()
	footer.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	footer.position = Vector2(-248, -54)
	footer.add_theme_constant_override("separation", 8)
	footer.z_index = 3
	add_child(footer)
	footer.add_child(_button("设置", "settings"))
	footer.add_child(_button("返回档案", "return"))


func _build_overlay() -> void:
	_overlay = _panel(Vector2.ZERO, Vector2(620, 440))
	_overlay.name = "GamePanel"
	_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_overlay.position = Vector2(-310, -220)
	_overlay.z_index = 8
	_overlay.visible = false
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	_overlay.add_child(content)
	var heading_row := HBoxContainer.new()
	content.add_child(heading_row)
	_overlay_title = _label("", 24, TEXT)
	_overlay_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_row.add_child(_overlay_title)
	var close := _button("关闭", "")
	close.pressed.connect(_overlay.hide)
	heading_row.add_child(close)
	_overlay_body = RichTextLabel.new()
	_overlay_body.bbcode_enabled = true
	_overlay_body.fit_content = true
	_overlay_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_overlay_body.add_theme_color_override("default_color", MUTED)
	content.add_child(_overlay_body)


func _panel(position: Vector2, size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = position
	panel.custom_minimum_size = size
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)
	return panel


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = Color("#718c79aa")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, action: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(88, 44)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_stylebox_override("normal", _button_style(Color("#20352e")))
	button.add_theme_stylebox_override("hover", _button_style(Color("#365647")))
	button.add_theme_stylebox_override("pressed", _button_style(Color("#476c58")))
	if not action.is_empty():
		button.pressed.connect(_on_action.bind(action))
	return button


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("#8ca99288")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style


func _on_action(action: String) -> void:
	match action:
		"return":
			exit_requested.emit()
		"world_map":
			_open_panel("世界地图", "[color=#a9d7bd]泫勃派[/color] · 当前所在\n\n当前可见：泫勃派城区。此处为安全据点。\n\n区域切换会在地图内容制作并接入后开放。")
		"inventory":
			_open_panel("背包", "背包暂未接入角色存档。")
		"character":
			_open_panel("角色", "角色档案与属性系统尚未接入。")
		"skills":
			_open_panel("武学", "武学配置尚未接入。")
		"quests":
			_open_panel("任务", "当前没有已接入的正式任务。")
		"official_shop":
			_open_panel("泫勃派补给商", "官方商店商品与价格配置尚未接入。\n不会展示虚构库存或余额。")
		"market":
			_open_panel("交易市场", "当前世界没有可验证的玩家挂单。市场交易接口尚未接入。")
		"blacksmith":
			_open_panel("泫勃派铁匠", "装备强化和修理服务尚未接入。")
		"settings":
			settings_requested.emit()


func _open_panel(title: String, body: String) -> void:
	_overlay_title.text = title
	_overlay_body.text = body
	_overlay.show()
