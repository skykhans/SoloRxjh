extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


func _initialize() -> void:
	var application: Node = MAIN_SCENE.instantiate()
	if not _require(application != null, "Main scene did not instantiate."):
		return
	root.add_child(application)
	await process_frame

	var archive_menu: Control = application.get("_archive_menu") as Control
	if not _require(
		archive_menu != null and application.get("app_state") == 1,
		"Application did not reach the archive menu."
	):
		return
	var yard_scene: PackedScene = load("res://scenes/training_yard.tscn") as PackedScene
	var yard: Node3D = yard_scene.instantiate() as Node3D
	application.add_child(yard)
	await process_frame
	if not _require(
		yard != null and application.get("_xuanbo_city") == null,
		"Training yard isolation setup failed."
	):
		return
	var player: CharacterBody3D = yard.get_node_or_null("Player") as CharacterBody3D
	var target: StaticBody3D = yard.get_node_or_null("TrainingTarget") as StaticBody3D
	var ground: StaticBody3D = yard.get_node_or_null("Ground") as StaticBody3D
	var ground_mesh: MeshInstance3D = (
		ground.get_child(0) as MeshInstance3D
		if ground != null and ground.get_child_count() > 0
		else null
	)
	var ground_material: ShaderMaterial = (
		ground_mesh.material_override as ShaderMaterial
		if ground_mesh != null
		else null
	)
	var training_status: Label = yard.find_child("TrainingStatus", true, false) as Label
	var sky: Sky = (
		(yard.get_node("WorldEnvironment") as WorldEnvironment).environment.sky
	)
	var sky_material: ProceduralSkyMaterial = sky.sky_material as ProceduralSkyMaterial
	if not _require(
		player != null
			and target != null
			and yard.get_node_or_null("WorldEnvironment") is WorldEnvironment
			and yard.get_node_or_null("Camera3D") is Camera3D
			and yard.get_node_or_null("HUD") is CanvasLayer
			and sky_material != null
			and _weapon_materials_are_styled(player)
			and yard.find_child("TrainingTitle", true, false) is Label
			and training_status != null
			and training_status.text == "练习演示 · 不保存角色进度",
		"Archive menu did not enter a complete training yard."
	):
		return
	if not _require(
		ground_material != null and ground_material.shader != null,
		"Training yard ground does not use the registered ground shader material."
	):
		return

	var starting_position: Vector3 = player.global_position
	Input.action_press("move_forward")
	for _frame: int in range(8):
		await physics_frame
	Input.action_release("move_forward")
	if not _require(
		player.global_position.z < starting_position.z - 0.1,
		"Forward movement did not advance the player."
	):
		return
	player.global_position = Vector3(30.95, 0.0, 0.0)
	player.velocity = Vector3.ZERO
	Input.action_press("move_right")
	for _frame: int in range(8):
		await physics_frame
	Input.action_release("move_right")
	if not _require(
		player.global_position.x <= 31.0,
		"Keyboard movement allowed the player to leave the training yard boundary."
	):
		return

	player.global_position = Vector3(0.0, 0.0, -1.0)
	player.velocity = Vector3.ZERO
	yard._face_direction(Vector3(0.0, 0.0, -1.0))
	var attack_landed: bool = yard._perform_practice_attack()
	var slash_sparks: Node3D = yard.find_child("WeaponSlashSparks", true, false) as Node3D
	if not _require(
		attack_landed
			and yard._target_health == 75
			and yard._target_respawn_timer == 0.0
			and yard.find_child("WeaponSlash", true, false) is MeshInstance3D
			and yard.find_child("WeaponSlashCore", true, false) is MeshInstance3D
			and yard.find_child("WeaponSlashTrail", true, false) is MeshInstance3D
			and yard.find_child("WeaponSlashGoldTrail", true, false) is MeshInstance3D
			and slash_sparks != null
			and slash_sparks.get_child_count() == 6
			and _weapon_edge_is_pulsing(player),
		"An in-range attack did not damage its target and create the layered jade-and-gold weapon effects."
	):
		return

	var blocked_attack: bool = yard._perform_practice_attack()
	if not _require(
		not blocked_attack and yard._target_health == 75,
		"Attack recovery did not prevent an immediate second hit."
	):
		return
	if not _require(
		training_status.text == "命中演练目标 · 不结算经验或物品",
		"Training attack did not clearly report its non-persistent result."
	):
		return
	yard._attack_cooldown = 0.0
	for _hit: int in range(3):
		yard._perform_practice_attack()
		yard._attack_cooldown = 0.0
	if not _require(
		yard._target_health == 0
			and yard._target_respawn_timer > 0.0
			and training_status.text == "目标倒地 · 2.5秒后恢复",
		"Training target defeat did not enter its timed recovery state."
	):
		return
	yard._respawn_training_target()
	if not _require(
		yard._target_health == 100
			and yard._target_model.visible
			and training_status.text == "练习演示 · 不保存角色进度",
		"Training target recovery did not restore the practice state."
	):
		return

	yard.queue_free()
	yard = null
	await process_frame

	print("Training yard movement and attack slice smoke test passed.")
	quit(0)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false


func _weapon_materials_are_styled(player: CharacterBody3D) -> bool:
	var sword: MeshInstance3D = player.find_child("Sword", true, false) as MeshInstance3D
	var body: MeshInstance3D = (
		player.find_child("fang_chen_Body", true, false) as MeshInstance3D
	)
	if (
		sword == null
		or sword.mesh == null
		or sword.mesh.get_surface_count() != 4
		or body == null
		or body.mesh == null
		or body.mesh.get_surface_count() != 6
	):
		return false
	for surface: int in range(4):
		var material: StandardMaterial3D = (
			sword.get_surface_override_material(surface) as StandardMaterial3D
		)
		if material == null:
			return false
	for surface: int in range(6):
		if (body.get_surface_override_material(surface) as StandardMaterial3D) == null:
			return false
	return (
		(sword.get_surface_override_material(3) as StandardMaterial3D).emission_enabled
			and is_equal_approx(
				(body.get_surface_override_material(3) as StandardMaterial3D).roughness,
				0.62
			)
	)


func _weapon_edge_is_pulsing(player: CharacterBody3D) -> bool:
	var sword: MeshInstance3D = player.find_child("Sword", true, false) as MeshInstance3D
	if sword == null:
		return false
	var edge: StandardMaterial3D = (
		sword.get_surface_override_material(3) as StandardMaterial3D
	)
	return edge != null and edge.emission_energy_multiplier >= 2.5
