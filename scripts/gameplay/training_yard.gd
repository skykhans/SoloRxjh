extends Node3D

signal exit_requested

const PLAYER_MODEL_PATH: String = "res://assets/models/characters/fang_chen.glb"
const TARGET_MODEL_PATH: String = "res://assets/models/characters/bamboo_beast.glb"
const BAMBOO_MODEL_PATH: String = "res://assets/models/characters/linglong_bamboo.glb"
const FONT_PATH: String = "res://assets/fonts/NotoSansCJKsc-Regular.otf"
const FANG_CHEN_SWORD_VISUAL: Script = preload(
	"res://scripts/fang_chen_sword_visual.gd"
)
const TARGET_MAX_HP: int = 100
const ATTACK_RANGE: float = 2.2
const ATTACK_RECOVERY_SECONDS: float = 0.5
const DODGE_SECONDS: float = 0.24
const PLAYER_AREA_LIMIT: float = 31.0

const COLOR_TEXT: Color = Color("#edf1e9")
const COLOR_MUTED: Color = Color("#a9b8ad")
const COLOR_ACCENT: Color = Color("#77d3b1")
const COLOR_HEALTH: Color = Color("#cf755e")
const COLOR_MANA: Color = Color("#719bc2")
const COLOR_PANEL: Color = Color("#17211ddc")

var _player: CharacterBody3D
var _player_visual: Node3D
var _player_animation: AnimationPlayer
var _weapon_edge_material: StandardMaterial3D
var _weapon_glow_tween: Tween
var _camera: Camera3D
var _target: StaticBody3D
var _target_collision: CollisionShape3D
var _target_model: Node3D
var _target_animation: AnimationPlayer
var _target_label: Label3D
var _target_health: int = TARGET_MAX_HP
var _target_respawn_timer: float = 0.0
var _target_selected: bool = true
var _attack_cooldown: float = 0.0
var _action_animation_timer: float = 0.0
var _dodge_timer: float = 0.0
var _dodge_direction: Vector3 = Vector3.ZERO
var _camera_yaw: float = 0.0
var _camera_pitch: float = 0.23
var _camera_distance: float = 7.0
var camera_distance: float:
	get:
		return _camera_distance
	set(value):
		_camera_distance = clampf(value, 3.0, 12.0)
var _orbiting: bool = false
var _move_destination: Vector3 = Vector3.ZERO
var _has_move_destination: bool = false
var _toast_timer: float = 0.0
var _toast_label: Label
var _target_title: Label
var _target_bar: ProgressBar
var _training_status: Label
var _player_animation_name: StringName = &""


func _ready() -> void:
	_build_environment()
	_build_player()
	_build_training_target()
	_build_hud()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_camera()
	_update_target_hud()


func _physics_process(delta: float) -> void:
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_action_animation_timer = maxf(0.0, _action_animation_timer - delta)
	_target_respawn_timer = maxf(0.0, _target_respawn_timer - delta)
	_toast_timer = maxf(0.0, _toast_timer - delta)

	if _toast_timer == 0.0:
		_toast_label.visible = false
	if _target_respawn_timer == 0.0 and _target_health <= 0:
		_respawn_training_target()
		_show_toast("演练目标已恢复。")

	if Input.is_action_just_pressed("dodge"):
		_begin_dodge()
	if _dodge_timer > 0.0:
		_dodge_timer = maxf(0.0, _dodge_timer - delta)

	var movement: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)
	var direction: Vector3 = Vector3.ZERO
	if movement.length_squared() > 0.0:
		_has_move_destination = false
		direction = Basis(Vector3.UP, _camera_yaw) * Vector3(movement.x, 0.0, movement.y)
	elif _has_move_destination:
		direction = _move_destination - _player.global_position
		direction.y = 0.0
		if direction.length() < 0.22:
			direction = Vector3.ZERO
			_has_move_destination = false
		else:
			direction = direction.normalized()

	if _dodge_timer > 0.0:
		_player.velocity.x = _dodge_direction.x * 13.0
		_player.velocity.z = _dodge_direction.z * 13.0
	elif direction.length_squared() > 0.0:
		direction = direction.normalized()
		var movement_speed: float = 7.0 if Input.is_action_pressed("run") else 4.5
		_player.velocity.x = direction.x * movement_speed
		_player.velocity.z = direction.z * movement_speed
		_face_direction(direction)
	else:
		_player.velocity.x = move_toward(_player.velocity.x, 0.0, 20.0 * delta)
		_player.velocity.z = move_toward(_player.velocity.z, 0.0, 20.0 * delta)

	if not _player.is_on_floor():
		_player.velocity.y -= 9.8 * delta
	else:
		_player.velocity.y = 0.0
	_player.move_and_slide()
	_player.global_position.x = clampf(
		_player.global_position.x,
		-PLAYER_AREA_LIMIT,
		PLAYER_AREA_LIMIT
	)
	_player.global_position.z = clampf(
		_player.global_position.z,
		-PLAYER_AREA_LIMIT,
		PLAYER_AREA_LIMIT
	)
	_update_player_animation(direction.length_squared() > 0.0)


func _process(delta: float) -> void:
	_update_camera()
	if _target_label != null and _target_label.visible:
		_target_label.look_at(_camera.global_position, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("close_or_pause"):
		exit_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("normal_attack"):
		_perform_practice_attack()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact"):
		_show_toast("练功目标不会掉落物品或经验。")
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _orbiting:
		var mouse_motion: InputEventMouseMotion = event
		_camera_yaw -= mouse_motion.relative.x * 0.005
		_camera_pitch = clampf(
			_camera_pitch + mouse_motion.relative.y * 0.003,
			0.08,
			0.7
		)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_orbiting = event.pressed
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_camera_distance = maxf(4.0, _camera_distance - 0.6)
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_camera_distance = minf(10.0, _camera_distance + 0.6)
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select_or_move(event.position)


func _build_environment() -> void:
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment: Environment = Environment.new()
	var sky: Sky = Sky.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#6e91a0")
	sky_material.sky_horizon_color = Color("#c7d4c4")
	sky_material.ground_bottom_color = Color("#465a4c")
	sky_material.ground_horizon_color = Color("#a2ad91")
	sky_material.sun_angle_max = 18.0
	sky.sky_material = sky_material
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b8c9bb")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	add_child(world_environment)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-43.0, -28.0, 0.0)
	sun.light_color = Color("#ffe1bb")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

	_add_ground()
	_add_path()
	_add_training_gate()
	_add_bamboo()
	_add_rocks()
	_add_pool()


func _add_ground() -> void:
	var ground: StaticBody3D = StaticBody3D.new()
	ground.name = "Ground"
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = Vector2(76.0, 76.0)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(Color("#66835e"), 0.92)
	ground.add_child(mesh_instance)

	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(76.0, 0.3, 76.0)
	collision.shape = shape
	collision.position.y = -0.15
	ground.add_child(collision)
	add_child(ground)


func _add_path() -> void:
	var path_colors: Array[Color] = [
		Color("#8d8f79"),
		Color("#a29b7b"),
		Color("#777f6d"),
		Color("#9a987c"),
	]
	for index: int in range(18):
		var stone: MeshInstance3D = MeshInstance3D.new()
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(1.3 + float(index % 3) * 0.22, 0.12, 0.82)
		stone.mesh = mesh
		stone.material_override = _material(path_colors[index % path_colors.size()], 0.88)
		stone.position = Vector3(
			sin(float(index) * 1.7) * 0.22,
			0.07,
			-1.3 - float(index) * 1.0
		)
		stone.rotation.y = sin(float(index)) * 0.08
		add_child(stone)


func _add_training_gate() -> void:
	var dark_wood: StandardMaterial3D = _material(Color("#382c26"), 0.83)
	var vermilion: StandardMaterial3D = _material(Color("#8c4738"), 0.8)
	_add_box(Vector3(0.0, 2.0, -20.0), Vector3(0.45, 4.0, 0.45), dark_wood)
	_add_box(Vector3(5.4, 2.0, -20.0), Vector3(0.45, 4.0, 0.45), dark_wood)
	_add_box(Vector3(2.7, 4.0, -20.0), Vector3(6.4, 0.55, 0.7), vermilion)
	_add_box(Vector3(2.7, 3.35, -20.0), Vector3(5.2, 0.25, 0.45), dark_wood)

	var sign: Label3D = Label3D.new()
	sign.text = "泫勃演武场"
	sign.font = load(FONT_PATH) as Font
	sign.font_size = 64
	sign.pixel_size = 0.008
	sign.position = Vector3(2.7, 4.65, -19.55)
	sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign.modulate = Color("#f2dba7")
	add_child(sign)


func _add_bamboo() -> void:
	var bamboo_scene: PackedScene = load(BAMBOO_MODEL_PATH) as PackedScene
	if bamboo_scene == null:
		push_error("无法加载正式竹林模型：%s" % BAMBOO_MODEL_PATH)
		return

	var positions: Array[Vector3] = [
		Vector3(-8.5, 0.0, -3.0),
		Vector3(-10.0, 0.0, -7.0),
		Vector3(-8.0, 0.0, -12.5),
		Vector3(-5.5, 0.0, -16.0),
		Vector3(8.5, 0.0, -3.5),
		Vector3(10.0, 0.0, -8.0),
		Vector3(8.2, 0.0, -13.0),
		Vector3(6.4, 0.0, -16.5),
		Vector3(-13.0, 0.0, 5.0),
		Vector3(-11.0, 0.0, 11.0),
		Vector3(13.0, 0.0, 7.0),
		Vector3(10.0, 0.0, 13.0),
	]
	for index: int in range(positions.size()):
		var bamboo: Node3D = bamboo_scene.instantiate() as Node3D
		if bamboo == null:
			push_error("竹林模型根节点不是Node3D。")
			return
		bamboo.position = positions[index]
		bamboo.rotation.y = float(index) * 0.71
		bamboo.scale = Vector3.ONE * (0.82 + float(index % 3) * 0.1)
		add_child(bamboo)


func _add_rocks() -> void:
	var rock_materials: Array[StandardMaterial3D] = [
		_material(Color("#626d63"), 0.96),
		_material(Color("#787b6b"), 0.96),
		_material(Color("#4f625e"), 0.95),
	]
	var positions: Array[Vector3] = [
		Vector3(-6.0, 0.35, 5.0),
		Vector3(-5.0, 0.45, -8.0),
		Vector3(-7.2, 0.3, -17.5),
		Vector3(6.5, 0.4, 4.5),
		Vector3(7.2, 0.35, -10.0),
		Vector3(5.8, 0.28, -16.8),
		Vector3(-15.0, 0.45, -1.0),
		Vector3(15.0, 0.42, 3.0),
	]
	for index: int in range(positions.size()):
		var rock: MeshInstance3D = MeshInstance3D.new()
		var mesh: SphereMesh = SphereMesh.new()
		mesh.radial_segments = 7
		mesh.rings = 4
		rock.mesh = mesh
		rock.material_override = rock_materials[index % rock_materials.size()]
		rock.position = positions[index]
		rock.scale = Vector3(
			0.7 + float(index % 3) * 0.24,
			0.65 + float(index % 2) * 0.2,
			0.72 + float(index % 4) * 0.12
		)
		rock.rotation = Vector3(float(index) * 0.14, float(index), float(index) * 0.08)
		add_child(rock)


func _add_pool() -> void:
	var water: MeshInstance3D = MeshInstance3D.new()
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = Vector2(9.0, 13.0)
	mesh.subdivide_width = 12
	mesh.subdivide_depth = 16
	water.mesh = mesh
	var material: StandardMaterial3D = _material(Color("#397f86"), 0.22)
	material.metallic = 0.08
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.9
	water.material_override = material
	water.position = Vector3(-16.5, 0.025, 8.0)
	add_child(water)


func _build_player() -> void:
	var player_model_scene: PackedScene = load(PLAYER_MODEL_PATH) as PackedScene
	if player_model_scene == null:
		push_error("无法加载正式玩家模型：%s" % PLAYER_MODEL_PATH)
		return
	_player = CharacterBody3D.new()
	_player.name = "Player"
	_player.position = Vector3(0.0, 0.0, 1.2)
	_player.floor_snap_length = 0.25
	_player.floor_max_angle = deg_to_rad(48.0)
	add_child(_player)

	var collision: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	_player.add_child(collision)

	_player_visual = Node3D.new()
	_player_visual.name = "Visual"
	_player.add_child(_player_visual)
	var model: Node3D = player_model_scene.instantiate() as Node3D
	if model == null:
		push_error("玩家模型根节点不是Node3D：%s" % PLAYER_MODEL_PATH)
		return
	_player_visual.add_child(model)
	var weapon_style_result: Dictionary = FANG_CHEN_SWORD_VISUAL.apply_to_model(model)
	if not weapon_style_result.get("ok", false):
		push_error("练功场武器样式初始化失败：%s" % weapon_style_result.get("error", "unknown"))
		return
	_weapon_edge_material = weapon_style_result["edge_material"]
	_player_animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _player_animation == null:
		push_error("玩家模型缺少AnimationPlayer：%s" % PLAYER_MODEL_PATH)
		return
	_play_animation(_player_animation, &"Idle", true)
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = 48.0
	_camera.near = 0.1
	_camera.far = 160.0
	_camera.current = true
	add_child(_camera)


func _build_training_target() -> void:
	var target_scene: PackedScene = load(TARGET_MODEL_PATH) as PackedScene
	if target_scene == null:
		push_error("无法加载正式竹熊模型：%s" % TARGET_MODEL_PATH)
		return
	_target = StaticBody3D.new()
	_target.name = "TrainingTarget"
	_target.position = Vector3(0.0, 0.0, -3.0)
	_target.add_to_group("training_target")
	add_child(_target)

	_target_collision = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.56
	capsule.height = 1.35
	_target_collision.shape = capsule
	_target_collision.position.y = 0.68
	_target.add_child(_target_collision)

	_target_model = target_scene.instantiate() as Node3D
	if _target_model == null:
		push_error("竹熊模型根节点不是Node3D：%s" % TARGET_MODEL_PATH)
		return
	_target_model.scale = Vector3.ONE * 0.9
	_target.add_child(_target_model)
	_target_animation = _target_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _target_animation == null:
		push_error("竹熊模型缺少AnimationPlayer：%s" % TARGET_MODEL_PATH)
		return
	_play_animation(_target_animation, &"Idle", true)

	_target_label = Label3D.new()
	_target_label.name = "TargetName"
	_target_label.text = "竹熊 · 演练目标"
	_target_label.font = load(FONT_PATH) as Font
	_target_label.font_size = 40
	_target_label.pixel_size = 0.006
	_target_label.position = Vector3(0.0, 2.4, 0.0)
	_target_label.modulate = COLOR_TEXT
	_target.add_child(_target_label)


func _build_hud() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = "HUD"
	canvas.layer = 10
	add_child(canvas)
	var root: Control = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	canvas.add_child(root)

	var status_panel: PanelContainer = PanelContainer.new()
	status_panel.position = Vector2(28.0, 26.0)
	status_panel.custom_minimum_size = Vector2(300.0, 92.0)
	status_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(status_panel)

	var status_content: VBoxContainer = VBoxContainer.new()
	status_content.add_theme_constant_override("separation", 5)
	status_panel.add_child(status_content)
	var training_title: Label = Label.new()
	training_title.name = "TrainingTitle"
	training_title.text = "演练场"
	training_title.add_theme_font_size_override("font_size", 20)
	training_title.add_theme_color_override("font_color", COLOR_TEXT)
	status_content.add_child(training_title)
	_training_status = Label.new()
	_training_status.name = "TrainingStatus"
	_training_status.text = "练习演示 · 不保存角色进度"
	_training_status.add_theme_font_size_override("font_size", 14)
	_training_status.add_theme_color_override("font_color", COLOR_MUTED)
	status_content.add_child(_training_status)

	var target_box: VBoxContainer = VBoxContainer.new()
	target_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	target_box.position = Vector2(-165.0, 28.0)
	target_box.custom_minimum_size = Vector2(330.0, 62.0)
	target_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(target_box)
	_target_title = Label.new()
	_target_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_title.add_theme_color_override("font_color", COLOR_TEXT)
	_target_title.add_theme_font_size_override("font_size", 18)
	target_box.add_child(_target_title)
	_target_bar = ProgressBar.new()
	_target_bar.custom_minimum_size = Vector2(330.0, 12.0)
	_target_bar.show_percentage = false
	_target_bar.add_theme_stylebox_override("background", _bar_style(Color("#2a3330")))
	_target_bar.add_theme_stylebox_override("fill", _bar_style(COLOR_HEALTH))
	target_box.add_child(_target_bar)

	var return_button: Button = Button.new()
	return_button.text = "返回档案"
	return_button.position = Vector2(-154.0, 28.0)
	return_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	return_button.custom_minimum_size = Vector2(126.0, 44.0)
	return_button.pressed.connect(_request_exit)
	return_button.add_theme_stylebox_override("normal", _button_style(Color("#263a34")))
	return_button.add_theme_stylebox_override("hover", _button_style(Color("#38594c")))
	return_button.add_theme_color_override("font_color", COLOR_TEXT)
	root.add_child(return_button)

	var hotbar: PanelContainer = PanelContainer.new()
	hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar.position = Vector2(-320.0, -92.0)
	hotbar.custom_minimum_size = Vector2(640.0, 64.0)
	hotbar.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(hotbar)
	var hotbar_content: HBoxContainer = HBoxContainer.new()
	hotbar_content.alignment = BoxContainer.ALIGNMENT_CENTER
	hotbar_content.add_theme_constant_override("separation", 10)
	hotbar.add_child(hotbar_content)
	for binding: Array in [
		["J", "普攻"],
		["Shift", "奔跑"],
		["Space", "闪避"],
		["右键", "镜头"],
	]:
		hotbar_content.add_child(_make_action_key(binding[0], binding[1]))

	_toast_label = Label.new()
	_toast_label.position = Vector2(30.0, -140.0)
	_toast_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_toast_label.add_theme_color_override("font_color", COLOR_ACCENT)
	_toast_label.add_theme_font_size_override("font_size", 17)
	_toast_label.visible = false
	root.add_child(_toast_label)


func _make_action_key(key_text: String, action_text: String) -> Control:
	var group: HBoxContainer = HBoxContainer.new()
	group.add_theme_constant_override("separation", 6)
	var key: Label = Label.new()
	key.text = key_text
	key.custom_minimum_size = Vector2(48.0, 38.0)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key.add_theme_color_override("font_color", COLOR_ACCENT)
	key.add_theme_font_size_override("font_size", 15)
	group.add_child(key)
	var label: Label = Label.new()
	label.text = action_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", COLOR_TEXT)
	group.add_child(label)
	return group


func _select_or_move(screen_position: Vector2) -> void:
	var origin: Vector3 = _camera.project_ray_origin(screen_position)
	var end: Vector3 = origin + _camera.project_ray_normal(screen_position) * 100.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [_player.get_rid()]
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Object = result.get("collider")
	if collider is Node and collider.is_in_group("training_target"):
		_target_selected = true
		_has_move_destination = false
		_training_status.text = "已锁定演练目标 · 不产生正式战利品"
		_update_target_hud()
		return
	if result.is_empty():
		return
	var destination: Vector3 = result["position"]
	destination.x = clampf(destination.x, -31.0, 31.0)
	destination.z = clampf(destination.z, -31.0, 31.0)
	destination.y = 0.0
	_move_destination = destination
	_has_move_destination = true


func _perform_practice_attack() -> bool:
	if _attack_cooldown > 0.0 or _target_health <= 0 or not _target_selected:
		return false
	var offset: Vector3 = _target.global_position - _player.global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance > ATTACK_RANGE or distance <= 0.001:
		_show_toast("演练目标超出普通攻击距离。")
		return false
	var forward: Vector3 = -_player_visual.global_basis.z
	if forward.dot(offset.normalized()) < cos(deg_to_rad(45.0)):
		_show_toast("请面向演练目标。")
		return false

	_attack_cooldown = ATTACK_RECOVERY_SECONDS
	_action_animation_timer = ATTACK_RECOVERY_SECONDS
	_play_animation(_player_animation, &"Attack1", false)
	_pulse_weapon_edge()
	_show_weapon_slash_effect(offset.normalized())
	_target_health = maxi(0, _target_health - 25)
	if _target_animation.has_animation(&"Hit"):
		_play_animation(_target_animation, &"Hit", false)
	if _target_health == 0:
		_target_respawn_timer = 2.5
		_target_collision.set_deferred("disabled", true)
		_target_model.visible = false
		_target_label.visible = false
		_training_status.text = "目标倒地 · 2.5秒后恢复"
		_show_toast("演练目标已击倒。")
	else:
		_training_status.text = "命中演练目标 · 不结算经验或物品"
		_show_toast("命中演练目标。")
	_update_target_hud()
	return true


func _pulse_weapon_edge() -> void:
	if _weapon_edge_material == null:
		return
	if _weapon_glow_tween != null and _weapon_glow_tween.is_running():
		_weapon_glow_tween.kill()
	_weapon_edge_material.emission_energy_multiplier = 2.6
	_weapon_glow_tween = create_tween()
	_weapon_glow_tween.tween_property(
		_weapon_edge_material,
		"emission_energy_multiplier",
		1.35,
		0.28
	)


func _show_weapon_slash_effect(direction: Vector3) -> void:
	var slash: MeshInstance3D = MeshInstance3D.new()
	slash.name = "WeaponSlash"
	var mesh: ArrayMesh = ArrayMesh.new()
	var vertices: PackedVector3Array = []
	var indices: PackedInt32Array = []
	const SEGMENTS: int = 18
	for segment: int in range(SEGMENTS + 1):
		var angle: float = lerpf(-1.05, 1.05, float(segment) / float(SEGMENTS))
		var inner: Vector3 = Vector3(sin(angle) * 0.72, cos(angle) * 0.72, 0.0)
		var outer: Vector3 = Vector3(sin(angle) * 0.98, cos(angle) * 0.98, 0.0)
		vertices.append(inner)
		vertices.append(outer)
	for segment: int in range(SEGMENTS):
		var base: int = segment * 2
		indices.append_array(PackedInt32Array([
			base,
			base + 1,
			base + 2,
			base + 1,
			base + 3,
			base + 2,
		]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	slash.mesh = mesh

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color("#7ffff0c9")
	material.emission_enabled = true
	material.emission = Color("#42e5c0")
	material.emission_energy_multiplier = 1.4
	slash.material_override = material

	var core: MeshInstance3D = MeshInstance3D.new()
	core.name = "WeaponSlashCore"
	core.mesh = mesh
	core.position.z = 0.012
	core.scale = Vector3(0.68, 0.68, 1.0)
	var core_material: StandardMaterial3D = StandardMaterial3D.new()
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	core_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	core_material.albedo_color = Color("#ecfff8d6")
	core_material.emission_enabled = true
	core_material.emission = Color("#d3fff2")
	core_material.emission_energy_multiplier = 2.1
	core.material_override = core_material
	slash.add_child(core)

	var toward_target: Vector3 = direction.normalized()
	add_child(slash)
	slash.global_position = (
		_target.global_position
		- toward_target * 0.35
		+ Vector3(0.0, 0.9, 0.0)
	)
	slash.rotation.y = _player_visual.rotation.y
	var fade: Tween = create_tween()
	fade.tween_property(material, "albedo_color:a", 0.0, 0.22)
	fade.parallel().tween_property(
		core_material,
		"albedo_color:a",
		0.0,
		0.22
	)
	fade.tween_callback(slash.queue_free)


func _begin_dodge() -> void:
	if _dodge_timer > 0.0:
		return
	var movement: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)
	if movement.length_squared() == 0.0:
		_dodge_direction = -_player_visual.global_basis.z
	else:
		_dodge_direction = Basis(Vector3.UP, _camera_yaw) * Vector3(
			movement.x,
			0.0,
			movement.y
		)
	_dodge_direction.y = 0.0
	_dodge_direction = _dodge_direction.normalized()
	_dodge_timer = DODGE_SECONDS
	_action_animation_timer = DODGE_SECONDS
	_play_animation(_player_animation, &"Dodge", false)


func _face_direction(direction: Vector3) -> void:
	_player_visual.rotation.y = atan2(-direction.x, -direction.z)


func _update_player_animation(moving: bool) -> void:
	if _action_animation_timer > 0.0:
		return
	if moving:
		_play_animation(
			_player_animation,
			&"Run" if Input.is_action_pressed("run") else &"Walk",
			true
		)
	else:
		_play_animation(_player_animation, &"Idle", true)


func _play_animation(
	player: AnimationPlayer,
	animation_name: StringName,
	looping: bool
) -> void:
	if player == null or not player.has_animation(animation_name):
		push_error("模型缺少所需动画：%s" % animation_name)
		return
	if _player_animation_name == animation_name and player == _player_animation:
		return
	var animation: Animation = player.get_animation(animation_name)
	animation.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	player.play(animation_name)
	if player == _player_animation:
		_player_animation_name = animation_name
	if player == _target_animation and animation_name == &"Hit":
		var finished_callback: Callable = _on_target_animation_finished
		if not player.animation_finished.is_connected(finished_callback):
			player.animation_finished.connect(finished_callback)


func _on_target_animation_finished(_animation_name: StringName) -> void:
	if _target_health > 0 and _target_animation != null:
		_play_animation(_target_animation, &"Idle", true)


func _update_camera() -> void:
	if _camera == null or _player == null:
		return
	var focus: Vector3 = _player.global_position + Vector3(0.0, 1.0, 0.0)
	var horizontal_distance: float = cos(_camera_pitch) * _camera_distance
	var offset: Vector3 = Vector3(
		sin(_camera_yaw) * horizontal_distance,
		sin(_camera_pitch) * _camera_distance + 0.7,
		cos(_camera_yaw) * horizontal_distance
	)
	_camera.global_position = focus + offset
	_camera.look_at(focus, Vector3.UP)


func _update_target_hud() -> void:
	if _target_title == null or _target_bar == null:
		return
	_target_title.text = (
		"竹熊  ·  %d / %d" % [_target_health, TARGET_MAX_HP]
		if _target_health > 0 and _target_selected
		else ""
	)
	_target_bar.value = float(_target_health)
	_target_title.visible = _target_health > 0 and _target_selected
	_target_bar.visible = _target_health > 0 and _target_selected


func _respawn_training_target() -> void:
	_target_health = TARGET_MAX_HP
	_target_collision.set_deferred("disabled", false)
	_target_model.visible = true
	_target_label.visible = true
	_target_animation.play(&"Idle")
	_training_status.text = "练习演示 · 不保存角色进度"
	_update_target_hud()


func _show_toast(message: String) -> void:
	_toast_label.text = message
	_toast_label.visible = true
	_toast_timer = 1.8


func _request_exit() -> void:
	exit_requested.emit()


func _add_box(position: Vector3, size: Vector3, material: Material) -> void:
	var box: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.material_override = material
	box.position = position
	add_child(box)


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.set_corner_radius_all(4)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	return style


func _bar_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(2)
	return style


func _button_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	return style
