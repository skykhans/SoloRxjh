extends SceneTree

const CATALOG: Script = preload("res://scripts/character_template_catalog.gd")
const CLASS_IDS: Array[String] = [
	"blade",
	"sword",
	"spear",
	"physician",
	"archer",
	"assassin",
	"musician",
	"fighter",
	"han_feiguan",
	"tan_hualing",
	"mei_liuzhen",
	"lu_fenglang",
	"dongling_shennv",
	"zhen_fengbai",
]


func _initialize() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://docs/contracts/角色初始模板.v1.json"
	)
	var json: JSON = JSON.new()
	if not _require(json.parse(source) == OK, "Initial character template contract did not parse."):
		quit(1)
		return
	var document: Dictionary = json.data
	var valid_document: Dictionary = CATALOG.validate_document(document)
	if not _require(
		valid_document.get("ok", false),
		"Valid initial character templates were rejected: %s" % valid_document.get("error", "")
	):
		quit(1)
		return
	for class_id: String in CLASS_IDS:
		var result: Dictionary = CATALOG.resolve(class_id)
		if not _require(
			result.get("ok", false) and result["template"]["class_id"] == class_id,
			"Template resolution failed for %s." % class_id
		):
			quit(1)
			return
	if not _require(
		not CATALOG.resolve("unknown").get("ok", false),
		"An unknown character class resolved to a template."
	):
		quit(1)
		return

	var missing_class: Dictionary = document.duplicate(true)
	missing_class["templates"].pop_back()
	if not _require(
		not CATALOG.validate_document(missing_class).get("ok", false),
		"A template registry missing a class was accepted."
	):
		quit(1)
		return
	var duplicate_class: Dictionary = document.duplicate(true)
	duplicate_class["templates"][1]["class_id"] = duplicate_class["templates"][0]["class_id"]
	if not _require(
		not CATALOG.validate_document(duplicate_class).get("ok", false),
		"A duplicated class template was accepted."
	):
		quit(1)
		return
	var missing_location_owner: Dictionary = document.duplicate(true)
	missing_location_owner.erase("location_state_ref")
	if not _require(
		not CATALOG.validate_document(missing_location_owner).get("ok", false),
		"A template without a location owner reference was accepted."
	):
		quit(1)
		return
	var wrong_location_pointer: Dictionary = document.duplicate(true)
	wrong_location_pointer["location_state_ref"]["pointer"] = "/missing_location"
	if not _require(
		not CATALOG.validate_document(wrong_location_pointer).get("ok", false),
		"A template with an invalid location owner pointer was accepted."
	):
		quit(1)
		return
	var invalid_location_schema: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://docs/contracts/世界图谱.v1.json")
	)
	invalid_location_schema["character_location"]["schema_ref"]["file"] = "随机序列.v1.json"
	if not _require(
		not CATALOG.validate_document(document, invalid_location_schema).get("ok", false),
		"A location owner with a non-location schema was accepted."
	):
		quit(1)
		return
	var world_graph: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://docs/contracts/世界图谱.v1.json")
	)
	if not _require(
		CATALOG._has_valid_birth_anchor_in_document(world_graph, "story_workcamp_start"),
		"The adopted birth anchor did not resolve to a valid world position."
	):
		quit(1)
		return
	var missing_birth_map: Dictionary = world_graph.duplicate(true)
	missing_birth_map["maps"] = missing_birth_map["maps"].filter(
		func(map: Dictionary) -> bool: return map["map_id"] != "story_valley_world"
	)
	if not _require(
		not CATALOG.validate_document(document, missing_birth_map).get("ok", false),
		"Templates with a birth anchor whose map is missing were accepted."
	):
		quit(1)
		return
	var duplicate_birth_anchor: Dictionary = world_graph.duplicate(true)
	var birth_anchor_copy: Dictionary = {}
	for anchor: Dictionary in duplicate_birth_anchor["anchors"]:
		if anchor["anchor_id"] == "story_workcamp_start":
			birth_anchor_copy = anchor.duplicate(true)
			break
	duplicate_birth_anchor["anchors"].append(birth_anchor_copy)
	if not _require(
		not CATALOG.validate_document(document, duplicate_birth_anchor).get("ok", false),
		"Templates with a duplicated birth anchor were accepted."
	):
		quit(1)
		return
	var out_of_bounds_birth_anchor: Dictionary = world_graph.duplicate(true)
	for anchor: Dictionary in out_of_bounds_birth_anchor["anchors"]:
		if anchor["anchor_id"] == "story_workcamp_start":
			anchor["position_feet_m"][0] = 161.0
			break
	if not _require(
		not CATALOG.validate_document(document, out_of_bounds_birth_anchor).get("ok", false),
		"Templates with an out-of-bounds birth anchor were accepted."
	):
		quit(1)
		return
	var invalid_birth_yaw: Dictionary = world_graph.duplicate(true)
	for anchor: Dictionary in invalid_birth_yaw["anchors"]:
		if anchor["anchor_id"] == "story_workcamp_start":
			anchor["yaw_radians"] = "north"
			break
	if not _require(
		not CATALOG.validate_document(document, invalid_birth_yaw).get("ok", false),
		"Templates with a birth anchor with a non-numeric yaw were accepted."
	):
		quit(1)
		return
	var non_finite_birth_position: Dictionary = world_graph.duplicate(true)
	for anchor: Dictionary in non_finite_birth_position["anchors"]:
		if anchor["anchor_id"] == "story_workcamp_start":
			anchor["position_feet_m"][1] = INF
			break
	if not _require(
		not CATALOG.validate_document(document, non_finite_birth_position).get("ok", false),
		"Templates with a birth anchor with a non-finite position were accepted."
	):
		quit(1)
		return
	var duplicate_birth_map: Dictionary = world_graph.duplicate(true)
	var birth_map_copy: Dictionary = {}
	for map: Dictionary in duplicate_birth_map["maps"]:
		if map["map_id"] == "story_valley_world":
			birth_map_copy = map.duplicate(true)
			break
	duplicate_birth_map["maps"].append(birth_map_copy)
	if not _require(
		not CATALOG.validate_document(document, duplicate_birth_map).get("ok", false),
		"Templates with a duplicated birth map were accepted."
	):
		quit(1)
		return

	var wrong_weapon: Dictionary = document.duplicate(true)
	wrong_weapon["templates"][0]["equipped_grants"][0]["item_id"] = "weapon_sword_wood"
	if not _require(
		not CATALOG.validate_document(wrong_weapon).get("ok", false),
		"A class template with a mismatched equipped weapon was accepted."
	):
		quit(1)
		return
	var wrong_bag: Dictionary = document.duplicate(true)
	wrong_bag["templates"][0]["bag_grants"][0]["quantity"] = 4
	if not _require(
		not CATALOG.validate_document(wrong_bag).get("ok", false),
		"A class template with an incomplete starter bag was accepted."
	):
		quit(1)
		return
	var missing_item: Dictionary = document.duplicate(true)
	missing_item["items"].erase(missing_item["items"][0])
	if not _require(
		not CATALOG.validate_document(missing_item).get("ok", false),
		"A template with an unresolved item definition was accepted."
	):
		quit(1)
		return
	var missing_quickbar_item: Dictionary = document.duplicate(true)
	missing_quickbar_item["items"].erase(
		missing_quickbar_item["items"].filter(
			func(item: Dictionary) -> bool: return item["item_id"] == "consumable_hp_small"
		)[0]
	)
	if not _require(
		not CATALOG.validate_document(missing_quickbar_item).get("ok", false),
		"A missing quickbar item definition was accepted."
	):
		quit(1)
		return
	var wrong_ability_class: Dictionary = document.duplicate(true)
	var initial_ability_id: String = wrong_ability_class["templates"][0]["learned_active_phases"][0]["ability_id"]
	for ability: Dictionary in wrong_ability_class["active_ability_definitions"]:
		if ability["ability_id"] == initial_ability_id:
			ability["class_id"] = "sword"
			break
	if not _require(
		not CATALOG.validate_document(wrong_ability_class).get("ok", false),
		"A template learned an ability belonging to another class."
	):
		quit(1)
		return
	var wrong_layout_policy: Dictionary = document.duplicate(true)
	wrong_layout_policy["equipment_layout_profile"]["selection_required"] = false
	if not _require(
		not CATALOG.validate_document(wrong_layout_policy).get("ok", false),
		"A template layout that permits an implicit fallback was accepted."
	):
		quit(1)
		return
	var fractional_silver: Dictionary = document.duplicate(true)
	fractional_silver["templates"][0]["silver"] = 2000.5
	if not _require(
		not CATALOG.validate_document(fractional_silver).get("ok", false),
		"A template with a fractional silver grant was accepted."
	):
		quit(1)
		return
	var duplicate_innate_profile: Dictionary = document.duplicate(true)
	duplicate_innate_profile["templates"][0]["declared_innate_profiles"] = [
		"duplicate_profile",
		"duplicate_profile",
	]
	if not _require(
		not CATALOG.validate_document(duplicate_innate_profile).get("ok", false),
		"A duplicated innate profile declaration was accepted."
	):
		quit(1)
		return
	var missing_initial_source: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://docs/contracts/角色创建.v1.json")
	)
	missing_initial_source["registered_initial_components"]["bindings"][0][
		"initial_value_ref"
	]["pointer"] = "/initial_state_profile/missing_component"
	var missing_source_text: String = JSON.stringify(missing_initial_source)
	var original_contract_text: String = FileAccess.get_file_as_string(
		"res://docs/contracts/角色创建.v1.json"
	)
	if not _require(
		not CATALOG._validate_initial_component_bindings_from_text(missing_source_text),
		"A registered initial component with a missing owner value was accepted."
	):
		quit(1)
		return
	var missing_binding: Dictionary = JSON.parse_string(original_contract_text)
	missing_binding["registered_initial_components"]["bindings"].pop_back()
	if not _require(
		not CATALOG._validate_initial_component_bindings_from_text(
			JSON.stringify(missing_binding)
		),
		"A creation contract missing a required character component binding was accepted."
	):
		quit(1)
		return
	var invalid_schema_reference: Dictionary = JSON.parse_string(original_contract_text)
	invalid_schema_reference["registered_initial_components"]["bindings"][0][
		"schema_ref"
	]["pointer"] = "/$comment"
	if not _require(
		not CATALOG._validate_initial_component_bindings_from_text(
			JSON.stringify(invalid_schema_reference)
		),
		"A component binding to a non-schema value was accepted."
	):
		quit(1)
		return
	var mismatched_qigong: Dictionary = JSON.parse_string(original_contract_text)
	mismatched_qigong["registered_initial_components"]["bindings"][5][
		"initial_value_ref"
	]["pointer"] = "/persistent_qigong_root/initial/allocations"
	if not _require(
		not CATALOG._validate_initial_component_bindings_from_text(
			JSON.stringify(mismatched_qigong)
		),
		"A qigong binding that does not match the owner initial root was accepted."
	):
		quit(1)
		return
	var missing_session_initial: Dictionary = JSON.parse_string(original_contract_text)
	missing_session_initial["registered_initial_components"]["bindings"][13][
		"initial_value_ref"
	]["pointer"] = "/character_initialization/missing"
	if not _require(
		not CATALOG._validate_initial_component_bindings_from_text(
			JSON.stringify(missing_session_initial)
		),
		"A session guard binding without an owner initial value was accepted."
	):
		quit(1)
		return

	print("Character template catalog checks passed.")
	quit(0)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	return false
