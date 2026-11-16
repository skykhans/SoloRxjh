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
	archive_menu.emit_signal("practice_requested")
	await process_frame
	var yard: Node3D = application.get("_training_yard") as Node3D
	if not _require(yard != null, "Archive menu did not create the training yard scene."):
		return
	var player: CharacterBody3D = yard.get_node_or_null("Player") as CharacterBody3D
	var target: StaticBody3D = yard.get_node_or_null("TrainingTarget") as StaticBody3D
	if not _require(
		application.get("app_state") == 2
			and player != null
			and target != null
			and yard.get_node_or_null("WorldEnvironment") is WorldEnvironment
			and yard.get_node_or_null("Camera3D") is Camera3D
			and yard.get_node_or_null("HUD") is CanvasLayer,
		"Archive menu did not enter a complete training yard."
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

	player.global_position = Vector3(0.0, 0.0, -1.0)
	player.velocity = Vector3.ZERO
	yard._face_direction(Vector3(0.0, 0.0, -1.0))
	if not _require(
		yard._perform_practice_attack()
			and yard._target_health == 75
			and yard._target_respawn_timer == 0.0,
		"An in-range facing practice attack did not damage only its target."
	):
		return

	var blocked_attack: bool = yard._perform_practice_attack()
	if not _require(
		not blocked_attack and yard._target_health == 75,
		"Attack recovery did not prevent an immediate second hit."
	):
		return

	yard._request_exit()
	await process_frame
	if not _require(
		application.get("app_state") == 1
			and archive_menu.visible
			and application.get("_training_yard") == null,
		"Training yard did not return cleanly to the archive menu."
	):
		return

	print("Training yard menu, movement, attack, and return smoke test passed.")
	quit(0)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false
