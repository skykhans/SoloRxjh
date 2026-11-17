extends RefCounted


static func apply_to_model(model: Node) -> Dictionary:
	var body: MeshInstance3D = model.find_child(
		"fang_chen_Body",
		true,
		false
	) as MeshInstance3D
	var sword: MeshInstance3D = model.find_child("Sword", true, false) as MeshInstance3D
	if (
		body == null
		or body.mesh == null
		or body.mesh.get_surface_count() != 6
		or sword == null
		or sword.mesh == null
		or sword.mesh.get_surface_count() != 4
	):
		return _failure("方尘角色缺少约定的人物网格或持剑材质表面。")

	var body_material_names: Array[String] = [
		"Worn leather",
		"Dark robe",
		"Servant teal cloth",
		"Warm skin",
		"Linen",
		"Ink hair",
	]
	for surface: int in range(body_material_names.size()):
		var source_material: Material = body.mesh.surface_get_material(surface)
		if source_material == null or source_material.resource_name != body_material_names[surface]:
			return _failure("方尘人物材质表面顺序无效：%s" % surface)

	var sword_material_names: Array[String] = [
		"Worn leather",
		"Rust",
		"Dark floating immortal sword",
		"Sword edge",
	]
	for surface: int in range(sword_material_names.size()):
		var source_material: Material = sword.mesh.surface_get_material(surface)
		if source_material == null or source_material.resource_name != sword_material_names[surface]:
			return _failure("方尘武器材质表面顺序无效：%s" % surface)

	var body_roughness: Array[float] = [0.76, 0.82, 0.7, 0.62, 0.85, 0.48]
	var body_metallic: Array[float] = [0.03, 0.0, 0.0, 0.0, 0.0, 0.02]
	for surface: int in range(body_material_names.size()):
		var source_material: StandardMaterial3D = (
			body.mesh.surface_get_material(surface) as StandardMaterial3D
		)
		var material: StandardMaterial3D = source_material.duplicate() as StandardMaterial3D
		material.roughness = body_roughness[surface]
		material.metallic = body_metallic[surface]
		body.set_surface_override_material(surface, material)

	var grip_material: StandardMaterial3D = StandardMaterial3D.new()
	grip_material.albedo_color = Color("#17352e")
	grip_material.metallic = 0.28
	grip_material.roughness = 0.42
	sword.set_surface_override_material(0, grip_material)

	var guard_material: StandardMaterial3D = StandardMaterial3D.new()
	guard_material.albedo_color = Color("#c6a35c")
	guard_material.metallic = 0.82
	guard_material.roughness = 0.27
	sword.set_surface_override_material(1, guard_material)

	var blade_material: StandardMaterial3D = StandardMaterial3D.new()
	blade_material.albedo_color = Color("#253c3c")
	blade_material.metallic = 0.92
	blade_material.roughness = 0.2
	blade_material.emission_enabled = true
	blade_material.emission = Color("#12493e")
	blade_material.emission_energy_multiplier = 0.38
	sword.set_surface_override_material(2, blade_material)

	var edge_material: StandardMaterial3D = StandardMaterial3D.new()
	edge_material.albedo_color = Color("#a9ffe9")
	edge_material.metallic = 0.58
	edge_material.roughness = 0.16
	edge_material.emission_enabled = true
	edge_material.emission = Color("#36efc0")
	edge_material.emission_energy_multiplier = 1.35
	sword.set_surface_override_material(3, edge_material)
	return {"ok": true, "edge_material": edge_material}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
