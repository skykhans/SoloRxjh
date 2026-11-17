extends RefCounted


static func apply_to_model(model: Node) -> Dictionary:
	var sword: MeshInstance3D = model.find_child("Sword", true, false) as MeshInstance3D
	if sword == null or sword.mesh == null or sword.mesh.get_surface_count() != 4:
		return _failure("方尘持剑模型缺少约定的四个材质表面。")

	var expected_materials: Array[String] = [
		"Worn leather",
		"Rust",
		"Dark floating immortal sword",
		"Sword edge",
	]
	for surface: int in range(expected_materials.size()):
		var source_material: Material = sword.mesh.surface_get_material(surface)
		if (
			source_material == null
			or source_material.resource_name != expected_materials[surface]
		):
			return _failure("方尘武器材质表面顺序无效：%s" % surface)

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
