extends SceneTree

const MODEL_PATH := "res://assets/models/characters/fang_chen.glb"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var city_scene := load("res://scenes/xuanbo_city.tscn") as PackedScene
	if not _require(city_scene != null, "泫勃派场景不存在。"):
		return
	var city := city_scene.instantiate() as Control
	root.add_child(city)
	await process_frame
	var portrait := city.find_child("CharacterPortrait", true, false) as SubViewportContainer
	var model := city.get("_model_pivot") as Node3D
	var overlay := city.find_child("GamePanel", true, false) as PanelContainer
	if not _require(
		(
			(DisplayServer.get_name() == "headless"
				and portrait == null
				and model == null
				and ResourceLoader.exists(MODEL_PATH))
			or (portrait != null and portrait.get_child_count() == 1 and model != null)
		) and overlay != null,
		"泫勃派人物或游戏面板未正确创建。"
	):
		return
	var status := city.find_child("PlayerStatus", true, false) as PanelContainer
	var status_text := status.get_child(0) as VBoxContainer if status != null else null
	if not _require(
		status_text != null
			and not (status_text.get_child(0) as Label).text.contains("方尘")
			and city.has_signal("settings_requested"),
		"首屏包含未验证的角色数据或未提供设置入口。"
	):
		return
	if model != null:
		var sword := model.find_child("Sword", true, false) as MeshInstance3D
		if not _require(sword != null, "人物持剑模型未加载。"):
			return
		var edge := sword.get_surface_override_material(3) as StandardMaterial3D
		if not _require(edge != null and edge.emission_enabled, "人物武器刃口特效材质缺失。"):
			return
	city.call("_on_action", "market")
	if not _require(
		overlay.visible and str(city.get("_overlay_title").text) == "交易市场",
		"交易市场入口无法打开对应界面。"
	):
		return
	city.queue_free()
	await process_frame
	print("泫勃派场景、人物、武器与交易面板检查通过。")
	quit(0)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false
