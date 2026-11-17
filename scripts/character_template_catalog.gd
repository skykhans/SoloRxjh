extends RefCounted

const TEMPLATE_PATH: String = "res://docs/contracts/角色初始模板.v1.json"
const CREATION_CONTRACT_PATH: String = "res://docs/contracts/角色创建.v1.json"
const WORLD_GRAPH_PATH: String = "res://docs/contracts/世界图谱.v1.json"
const STRICT_JSON: Script = preload("res://scripts/strict_json.gd")
const JSON_SCHEMA_VALIDATOR: Script = preload("res://scripts/json_schema_validator.gd")
const IDENTITY_VALIDATOR: Script = preload("res://scripts/character_identity_validator.gd")
const INITIAL_COMPONENT_FIELDS: PackedStringArray = [
	"character.basic_combo_window_or_null",
	"character.customization",
	"character.earth_spirit_points",
	"character.training_gate_buffs",
	"character.training_gate_daily",
	"character.qigong",
	"character.martial_merit_title_state",
	"character.quests.adv_03_upper",
	"character.quests.adv_03",
	"character.activities",
	"character.quests.adv_01",
	"character.quests.adv_02",
	"character.quests.ref_QREF-63791-016",
	"character.pending_play_session",
]
const TEMPLATE_KEYS: PackedStringArray = [
	"template_id",
	"class_id",
	"starting_weapon_id",
	"initial_state_profile",
	"base_growth_ref",
	"birth_anchor_id",
	"equipment_layout_profile",
	"active_loadout_id",
	"equipped_grants",
	"bag_grants",
	"silver",
	"basic_attack_profile_id",
	"learned_active_phases",
	"skill_bar",
	"item_bar",
	"declared_innate_profiles",
	"innate_profile_owner_file",
]
const EQUIPMENT_SLOTS: PackedStringArray = [
	"weapon",
	"body",
	"inner_armor",
	"glove_a",
	"glove_b",
	"boots",
	"necklace",
	"earring_a",
	"earring_b",
	"ring_a",
	"ring_b",
	"cape",
	"sect_uniform",
	"decoration",
]
const INITIAL_BAG_GRANTS: Array[Dictionary] = [
	{"item_id": "consumable_hp_small", "quantity": 5},
	{"item_id": "consumable_mana_ginseng", "quantity": 5},
]
const BIRTH_ANCHOR_ID: String = "story_workcamp_start"


static func resolve(class_id: Variant) -> Dictionary:
	if typeof(class_id) != TYPE_STRING or not IDENTITY_VALIDATOR.CLASS_IDS.has(class_id):
		return _failure("Character class is not one of the fourteen supported identities.")
	var file: FileAccess = FileAccess.open(TEMPLATE_PATH, FileAccess.READ)
	if file == null:
		return _failure("Character template contract is unreadable.")
	var source: String = file.get_as_text()
	if STRICT_JSON.has_duplicate_object_keys(source):
		return _failure("Character template contract contains duplicate object keys.")
	var json: JSON = JSON.new()
	if json.parse(source) != OK:
		return _failure("Character template contract is invalid JSON.")
	var validation: Dictionary = validate_document(json.data)
	if not validation.get("ok", false):
		return validation
	for template: Dictionary in json.data["templates"]:
		if template["class_id"] == class_id:
			return {"ok": true, "template": template.duplicate(true)}
	return _failure("Character template is missing the requested class.")


static func resolve_initial_components() -> Dictionary:
	var contract: Variant = _read_json_contract(CREATION_CONTRACT_PATH)
	if not contract is Dictionary:
		return _failure("Character creation contract is unreadable.")
	var components: Dictionary = {}
	var validation_error: Array[String] = []
	if not _validate_initial_component_bindings_from_document(
		contract,
		components,
		true,
		validation_error
	):
		return _failure(
			validation_error[0]
			if not validation_error.is_empty()
			else "Character initial component source bindings are invalid."
		)
	return {
		"ok": true,
		"components": components,
	}


static func validate_document(
		document: Variant,
		world_graph_override: Variant = null
) -> Dictionary:
	if not document is Dictionary:
		return _failure("Character template contract root must be an object.")
	if (
		not document.get("templates") is Array
		or document["templates"].size() != IDENTITY_VALIDATOR.CLASS_IDS.size()
		or not document.get("items") is Array
		or not document.get("initial_state_profile") is Dictionary
		or not document.get("equipment_layout_profile") is Dictionary
		or not document.get("basic_attack_profiles") is Array
		or not document.get("active_ability_definitions") is Array
		or not _validate_location_state_ref(document, world_graph_override)
		or not _validate_initial_component_bindings()
	):
		return _failure("Character template contract or initial component source bindings are invalid.")

	var items_by_id: Dictionary = {}
	for item_value: Variant in document["items"]:
		if (
			not item_value is Dictionary
			or typeof(item_value.get("item_id")) != TYPE_STRING
			or item_value["item_id"].strip_edges().is_empty()
			or items_by_id.has(item_value["item_id"])
		):
			return _failure("Character template item registry has an invalid or duplicate ID.")
		items_by_id[item_value["item_id"]] = item_value

	var attack_profiles: Dictionary = {}
	for attack_value: Variant in document["basic_attack_profiles"]:
		if (
			not attack_value is Dictionary
			or typeof(attack_value.get("basic_profile_id")) != TYPE_STRING
			or attack_value["basic_profile_id"].strip_edges().is_empty()
			or typeof(attack_value.get("class_id")) != TYPE_STRING
			or not IDENTITY_VALIDATOR.CLASS_IDS.has(attack_value["class_id"])
			or attack_profiles.has(attack_value["basic_profile_id"])
		):
			return _failure("Character template basic attack registry has an invalid or duplicate ID.")
		attack_profiles[attack_value["basic_profile_id"]] = attack_value["class_id"]

	var abilities_by_id: Dictionary = {}
	for ability_value: Variant in document["active_ability_definitions"]:
		if (
			not ability_value is Dictionary
			or typeof(ability_value.get("ability_id")) != TYPE_STRING
			or ability_value["ability_id"].strip_edges().is_empty()
			or typeof(ability_value.get("class_id")) != TYPE_STRING
			or not IDENTITY_VALIDATOR.CLASS_IDS.has(ability_value["class_id"])
			or not _is_exact_integer(ability_value.get("initial_phase"), 1)
			or abilities_by_id.has(ability_value["ability_id"])
		):
			return _failure("Character template ability registry has an invalid or duplicate entry.")
		abilities_by_id[ability_value["ability_id"]] = ability_value

	var layout: Dictionary = document["equipment_layout_profile"]
	if (
		not _has_exact_keys(
			layout,
			PackedStringArray(["id", "sets", "selection_required", "missing_profile_or_slot"])
		)
		or layout.get("id") != "two_empty_sets_14_slots"
		or layout.get("selection_required") != true
		or layout.get("missing_profile_or_slot") != "reject; never borrow sword template"
		or not layout.get("sets") is Dictionary
		or not _has_exact_keys(layout["sets"], ["primary", "secondary"])
	):
		return _failure("Character template starting equipment layout is invalid.")
	for loadout_id: String in ["primary", "secondary"]:
		var slots: Variant = layout["sets"][loadout_id]
		if not slots is Dictionary or not _has_exact_keys(slots, EQUIPMENT_SLOTS):
			return _failure("Character template equipment layout has an invalid slot set.")
		for slot_id: String in EQUIPMENT_SLOTS:
			if slots[slot_id] != null:
				return _failure("Character template base equipment layout must be empty.")

	var seen_classes: Dictionary = {}
	for template_value: Variant in document["templates"]:
		if (
			not template_value is Dictionary
			or not _has_exact_keys(template_value, TEMPLATE_KEYS)
		):
			return _failure("Character template does not match its strict registry projection.")
		var template: Dictionary = template_value
		var class_id: Variant = template["class_id"]
		if (
			typeof(class_id) != TYPE_STRING
			or not IDENTITY_VALIDATOR.CLASS_IDS.has(class_id)
			or seen_classes.has(class_id)
		):
			return _failure("Character template classes are invalid or duplicated.")
		seen_classes[class_id] = true
		var template_error: String = _validate_template(
			template,
			document,
			items_by_id,
			attack_profiles,
			abilities_by_id,
			world_graph_override
		)
		if not template_error.is_empty():
			return _failure("%s: %s" % [class_id, template_error])

	for class_id: String in IDENTITY_VALIDATOR.CLASS_IDS:
		if not seen_classes.has(class_id):
			return _failure("Character template registry does not cover all fourteen classes.")
	return {"ok": true}


static func _validate_location_state_ref(
		template_contract: Dictionary,
		world_graph_override: Variant = null
) -> bool:
	var reference: Variant = template_contract.get("location_state_ref")
	if (
		not reference is Dictionary
		or not _has_exact_keys(reference, ["file", "pointer"])
		or reference.get("file") != "世界图谱.v1.json"
		or reference.get("pointer") != "/character_location"
	):
		return false
	var world_graph: Variant = world_graph_override
	if world_graph == null:
		world_graph = _read_json_contract(WORLD_GRAPH_PATH)
	if not world_graph is Dictionary:
		return false
	var location_owner: Variant = world_graph.get("character_location")
	if (
		not location_owner is Dictionary
		or location_owner.get("field") != "character.location"
		or not location_owner.get("schema_ref") is Dictionary
		or not _has_exact_keys(location_owner["schema_ref"], ["file", "pointer"])
	):
		return false
	var schema_reference: Dictionary = location_owner["schema_ref"]
	if (
		schema_reference.get("file") != "角色位置.schema.json"
		or schema_reference.get("pointer") != ""
	):
		return false
	var schema_result: Dictionary = _resolve_contract_pointer(
		schema_reference["file"],
		schema_reference["pointer"]
	)
	return (
		schema_result.get("ok", false)
		and _is_json_schema(schema_result.get("value"))
		and schema_result["value"].get("required") == ["map_id", "position", "yaw"]
	)


static func _validate_template(
	template: Dictionary,
	document: Dictionary,
	items_by_id: Dictionary,
	attack_profiles: Dictionary,
	abilities_by_id: Dictionary,
	world_graph_override: Variant = null
) -> String:
	var class_id: String = template["class_id"]
	var state: Dictionary = document["initial_state_profile"]
	var expected_weapon: Variant = template["starting_weapon_id"]
	var weapon: Variant = items_by_id.get(expected_weapon)
	var clothing: Variant = items_by_id.get("armor_apprentice_shirt")
	if (
		template["template_id"] != "new_" + class_id
		or template["initial_state_profile"] != state.get("id")
		or not template["base_growth_ref"] is Dictionary
		or not _has_exact_keys(template["base_growth_ref"], ["file", "class_id"])
		or template["base_growth_ref"].get("file") != "职业基础成长.v1.json"
		or template["base_growth_ref"].get("class_id") != class_id
		or template["birth_anchor_id"] != BIRTH_ANCHOR_ID
		or not _has_valid_birth_anchor(template["birth_anchor_id"], world_graph_override)
		or template["equipment_layout_profile"] != "two_empty_sets_14_slots"
		or template["active_loadout_id"] != "primary"
		or not _is_exact_integer(template["silver"], 2000)
		or typeof(template["basic_attack_profile_id"]) != TYPE_STRING
		or attack_profiles.get(template["basic_attack_profile_id"]) != class_id
		or not weapon is Dictionary
		or weapon.get("slot") != "weapon"
		or weapon.get("class_id") != class_id
		or weapon.get("initial_instance_profile") not in [
			"ordinary_initial_equipment",
			"hero_sealed_equipment",
		]
		or not clothing is Dictionary
		or clothing.get("slot") != "body"
		or not clothing.get("allowed_classes") is Array
		or not clothing["allowed_classes"].has(class_id)
	):
		return "Template identity or referenced starting definitions are inconsistent."
	if (
		not template["equipped_grants"] is Array
		or template["equipped_grants"].size() != 2
		or not _is_equipped_grant(template["equipped_grants"][0], "weapon", expected_weapon)
		or not _is_equipped_grant(
			template["equipped_grants"][1],
			"body",
			"armor_apprentice_shirt"
		)
	):
		return "Template must grant its class weapon and apprentice shirt in the primary set."
	if (
		not template["bag_grants"] is Array
		or not _is_initial_bag_grants(template["bag_grants"])
	):
		return "Template bag grants must match the two adopted five-item starter stacks."
	if not _validate_initial_abilities(template, abilities_by_id, items_by_id):
		return "Template initial abilities or quickbars are inconsistent."
	return ""


static func _validate_initial_component_bindings() -> bool:
	var file_contract: Variant = _read_json_contract(CREATION_CONTRACT_PATH)
	return _validate_initial_component_bindings_from_document(file_contract)


static func _validate_initial_component_bindings_from_text(source: String) -> bool:
	if STRICT_JSON.has_duplicate_object_keys(source):
		return false
	var json: JSON = JSON.new()
	if json.parse(source) != OK:
		return false
	return _validate_initial_component_bindings_from_document(json.data)


static func _validate_initial_component_bindings_from_document(
	contract: Variant,
	resolved_components: Variant = null,
	validate_initial_values: bool = false,
	validation_error: Array[String] = []
) -> bool:
	if (
		not contract is Dictionary
		or not contract.get("registered_initial_components") is Dictionary
	):
		return false
	var registry: Variant = contract["registered_initial_components"].get("bindings")
	if not registry is Array or registry.size() != INITIAL_COMPONENT_FIELDS.size():
		return false
	var seen_fields: Dictionary = {}
	var schema_validator: RefCounted = (
		JSON_SCHEMA_VALIDATOR.new()
		if validate_initial_values
		else null
	)
	for binding: Variant in registry:
		if (
			not binding is Dictionary
			or not _has_exact_keys(
				binding,
				PackedStringArray(["character_field", "initial_value_ref", "schema_ref"])
			)
			or not binding["initial_value_ref"] is Dictionary
			or not _has_exact_keys(binding["initial_value_ref"], ["file", "pointer"])
			or not binding["schema_ref"] is Dictionary
			or not _has_exact_keys(binding["schema_ref"], ["file", "pointer"])
		):
			return false
		var field: Variant = binding["character_field"]
		if (
			typeof(field) != TYPE_STRING
			or not INITIAL_COMPONENT_FIELDS.has(field)
			or seen_fields.has(field)
		):
			return false
		var source: Dictionary = binding["initial_value_ref"]
		var schema: Dictionary = binding["schema_ref"]
		var source_result: Dictionary = _resolve_contract_pointer(
			source.get("file", ""),
			source.get("pointer", "")
		) if typeof(source.get("file")) == TYPE_STRING and typeof(
			source.get("pointer")
		) == TYPE_STRING else _failure("Initial value reference is not a string pair.")
		var schema_result: Dictionary = _resolve_contract_pointer(
			schema.get("file", ""),
			schema.get("pointer", "")
		) if typeof(schema.get("file")) == TYPE_STRING and typeof(
			schema.get("pointer")
		) == TYPE_STRING else _failure("Schema reference is not a string pair.")
		if (
			not source_result.get("ok", false)
			or not schema_result.get("ok", false)
			or not _is_json_schema(schema_result.get("value"))
		):
			return false
		if field == "character.qigong" and not _qigong_initial_matches_owner(
			source_result["value"]
		):
			return false
		if validate_initial_values:
			var instance_validation: Dictionary = schema_validator.validate(
				source_result["value"],
				schema_result["value"]
			)
			if not instance_validation.get("ok", false):
				validation_error.append(
					"%s initial value violates its schema: %s"
					% [field, instance_validation.get("error", "unknown schema error")]
				)
				return false
		seen_fields[field] = true
		if resolved_components is Dictionary:
			resolved_components[field.trim_prefix("character.")] = _copy_value(
				source_result["value"]
			)
	for field: String in INITIAL_COMPONENT_FIELDS:
		if not seen_fields.has(field):
			return false
	return true


static func _is_json_schema(value: Variant) -> bool:
	return (
		value is Dictionary
		and typeof(value.get("$schema")) == TYPE_STRING
		and value["$schema"] == "https://json-schema.org/draft/2020-12/schema"
		and typeof(value.get("$id")) == TYPE_STRING
		and not value["$id"].strip_edges().is_empty()
	)


static func _qigong_initial_matches_owner(value: Variant) -> bool:
	var owner: Variant = _read_json_contract(
		"res://docs/contracts/气功学习与秘籍.v1.json"
	)
	if (
		not owner is Dictionary
		or not owner.get("persistent_qigong_root") is Dictionary
		or not owner["persistent_qigong_root"].get("initial") is Dictionary
		or not value is Dictionary
		or value.size() != 8
		or owner["persistent_qigong_root"]["initial"].size() != 8
	):
		return false
	return value == owner["persistent_qigong_root"]["initial"]


static func _resolve_contract_pointer(relative_path: String, pointer: String) -> Dictionary:
	if (
		relative_path.is_absolute_path()
		or relative_path.contains(":")
		or relative_path.begins_with("/")
	):
		return _failure("Contract reference path must be project-relative.")
	var normalized_path: String = relative_path.replace("\\", "/")
	var path: String = "res://docs/contracts".path_join(normalized_path).simplify_path()
	if not path.begins_with("res://docs/contracts/") or not FileAccess.file_exists(path):
		return _failure("Referenced contract file does not exist.")
	var data: Variant = _read_json_contract(path)
	if data == null or (not pointer.is_empty() and not pointer.begins_with("/")):
		return _failure("Referenced contract or JSON Pointer is invalid.")
	if pointer.is_empty():
		return {"ok": true, "value": data}
	var value: Variant = data
	for encoded_token: String in pointer.trim_prefix("/").split("/"):
		if encoded_token.contains("~") and encoded_token.replace("~0", "").replace("~1", "").contains("~"):
			return _failure("JSON Pointer contains an invalid escape.")
		var token: String = encoded_token.replace("~1", "/").replace("~0", "~")
		if value is Dictionary:
			if not value.has(token):
				return _failure("JSON Pointer object member does not exist.")
			value = value[token]
		elif value is Array:
			if not _is_array_index(token) or int(token) >= value.size():
				return _failure("JSON Pointer array index does not exist.")
			value = value[int(token)]
		else:
			return _failure("JSON Pointer traverses a scalar value.")
	return {"ok": true, "value": value}


static func _read_json_contract(path: String) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var source: String = file.get_as_text()
	if STRICT_JSON.has_duplicate_object_keys(source):
		return null
	var json: JSON = JSON.new()
	if json.parse(source) != OK:
		return null
	return json.data


static func _is_array_index(value: String) -> bool:
	if value.is_empty() or (value.length() > 1 and value.begins_with("0")):
		return false
	for index: int in range(value.length()):
		if value.unicode_at(index) not in range(48, 58):
			return false
	return true


static func _has_valid_birth_anchor(
		anchor_id: String,
		world_graph_override: Variant = null
) -> bool:
	var world_graph: Variant = world_graph_override
	if world_graph == null:
		world_graph = _read_json_contract(WORLD_GRAPH_PATH)
	return _has_valid_birth_anchor_in_document(
		world_graph,
		anchor_id
	)


static func _has_valid_birth_anchor_in_document(
		world: Variant,
		anchor_id: String
) -> bool:
	if (
		not world is Dictionary
		or not world.get("maps") is Array
		or not world.get("anchors") is Array
	):
		return false
	var matching_anchors: Array = world["anchors"].filter(
		func(anchor: Variant) -> bool:
			return anchor is Dictionary and anchor.get("anchor_id") == anchor_id
	)
	if matching_anchors.size() != 1:
		return false
	var anchor: Dictionary = matching_anchors[0]
	var map_id: Variant = anchor.get("map_id")
	var position: Variant = anchor.get("position_feet_m")
	if (
		typeof(map_id) != TYPE_STRING
		or not position is Array
		or position.size() != 3
		or not _is_finite_number(anchor.get("yaw_radians"))
	):
		return false
	for coordinate: Variant in position:
		if not _is_finite_number(coordinate):
			return false
	var matching_maps: Array = world["maps"].filter(
		func(map: Variant) -> bool:
			return map is Dictionary and map.get("map_id") == map_id
	)
	if matching_maps.size() != 1:
		return false
	var map: Dictionary = matching_maps[0]
	var x_bounds: Variant = map.get("x_bounds_m")
	var z_bounds: Variant = map.get("z_bounds_m")
	return (
		x_bounds is Array
		and x_bounds.size() == 2
		and _is_finite_number(x_bounds[0])
		and _is_finite_number(x_bounds[1])
		and float(x_bounds[0]) <= float(position[0])
		and float(position[0]) <= float(x_bounds[1])
		and z_bounds is Array
		and z_bounds.size() == 2
		and _is_finite_number(z_bounds[0])
		and _is_finite_number(z_bounds[1])
		and float(z_bounds[0]) <= float(position[2])
		and float(position[2]) <= float(z_bounds[1])
	)


static func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))


static func _validate_initial_abilities(
	template: Dictionary,
	abilities_by_id: Dictionary,
	items_by_id: Dictionary
) -> bool:
	var learned: Variant = template.get("learned_active_phases")
	var skill_bar: Variant = template.get("skill_bar")
	var innate_profiles: Variant = template.get("declared_innate_profiles")
	if (
		not learned is Array
		or learned.is_empty()
		or learned.size() > 4
		or not skill_bar is Array
		or skill_bar.size() != 4
		or template.get("item_bar") != [
			"consumable_hp_small",
			"consumable_mana_ginseng",
			null,
		]
		or not innate_profiles is Array
		or typeof(template.get("innate_profile_owner_file")) != TYPE_STRING
		or template["innate_profile_owner_file"].strip_edges().is_empty()
	):
		return false
	for item_id: String in ["consumable_hp_small", "consumable_mana_ginseng"]:
		if not items_by_id.has(item_id):
			return false
	var seen_innate_profiles: Dictionary = {}
	for profile_id: Variant in innate_profiles:
		if (
			typeof(profile_id) != TYPE_STRING
			or profile_id.strip_edges().is_empty()
			or seen_innate_profiles.has(profile_id)
		):
			return false
		seen_innate_profiles[profile_id] = true
	var seen_abilities: Dictionary = {}
	for index: int in range(learned.size()):
		var ability: Variant = learned[index]
		if (
			not ability is Dictionary
			or not _has_exact_keys(ability, PackedStringArray(["ability_id", "phase"]))
			or typeof(ability.get("ability_id")) != TYPE_STRING
			or ability["ability_id"].strip_edges().is_empty()
			or not _is_exact_integer(ability.get("phase"), 1)
			or seen_abilities.has(ability["ability_id"])
			or skill_bar[index] != ability["ability_id"]
			or not abilities_by_id.has(ability["ability_id"])
		):
			return false
		var definition: Dictionary = abilities_by_id[ability["ability_id"]]
		if (
			definition["class_id"] != template["class_id"]
			or definition["initial_phase"] != ability["phase"]
		):
			return false
		seen_abilities[ability["ability_id"]] = true
	for index: int in range(learned.size(), skill_bar.size()):
		if skill_bar[index] != null:
			return false
	return true


static func _is_equipped_grant(value: Variant, expected_slot: String, expected_item_id: String) -> bool:
	return (
		value is Dictionary
		and _has_exact_keys(value, ["loadout_id", "slot", "item_id", "quantity"])
		and value["loadout_id"] == "primary"
		and value["slot"] == expected_slot
		and value["item_id"] == expected_item_id
		and _is_exact_integer(value["quantity"], 1)
	)


static func _is_initial_bag_grants(value: Array) -> bool:
	if value.size() != INITIAL_BAG_GRANTS.size():
		return false
	for index: int in range(INITIAL_BAG_GRANTS.size()):
		var grant: Variant = value[index]
		if (
			not grant is Dictionary
			or not _has_exact_keys(grant, PackedStringArray(["item_id", "quantity"]))
			or grant["item_id"] != INITIAL_BAG_GRANTS[index]["item_id"]
			or not _is_exact_integer(
				grant["quantity"],
				INITIAL_BAG_GRANTS[index]["quantity"]
			)
		):
			return false
	return true


static func _is_exact_integer(value: Variant, expected: int) -> bool:
	if typeof(value) == TYPE_INT:
		return value == expected
	if typeof(value) != TYPE_FLOAT:
		return false
	var number: float = value
	return is_finite(number) and floorf(number) == number and number == expected


static func _copy_value(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value


static func _has_exact_keys(value: Dictionary, expected_keys: PackedStringArray) -> bool:
	if value.size() != expected_keys.size():
		return false
	for key: String in expected_keys:
		if not value.has(key):
			return false
	return true


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
