extends RefCounted

const MATERIAL_AGGREGATION: Script = preload(
	"res://scripts/gameplay/recommendation_material_aggregation.gd"
)
const EXPERIENCE_AWARD: Script = preload(
	"res://scripts/gameplay/recommendation_experience_award.gd"
)
const CANONICAL_JSON: Script = preload("res://scripts/canonical_json.gd")
const MAX_SAFE_INTEGER: int = 9007199254740991
const QUEST_ID: String = "ref_QREF-63791-016"
const RECOMMENDATION_ITEM_ID: String = "adv02_recommendation"


static func build_committed_candidate(
	reserved_event: Variant,
	character_before: Variant,
	source_flows_before: Variant,
	existing_object_ids: Variant,
	experience_records: Variant,
	award_records: Variant
) -> Dictionary:
	if not reserved_event is Dictionary or reserved_event.size() != 4:
		return _failure("Reserved recommendation event has an invalid shape.")
	if (
		reserved_event.get("phase") != "reserved"
		or not reserved_event.get("identity") is Dictionary
		or not reserved_event.get("command") is Dictionary
		or not reserved_event.get("plan") is Dictionary
	):
		return _failure("A reserved recommendation event is required.")
	if not _has_exact_keys(reserved_event, ["phase", "identity", "command", "plan"]):
		return _failure("Reserved recommendation event contains unexpected fields.")
	if not character_before is Dictionary or character_before.size() != 8:
		return _failure("Current character state has an invalid shape.")
	var state_keys: Array[String] = [
		"character_id",
		"revision",
		"inventory_revision",
		"quest",
		"inventory",
		"item_stacks",
		"progress",
		"qigong",
	]
	if not _has_exact_keys(character_before, state_keys):
		return _failure("Current character state does not match its strict projection.")
	var identity: Dictionary = reserved_event["identity"]
	var command: Dictionary = reserved_event["command"]
	var plan: Dictionary = reserved_event["plan"]
	if not _has_exact_keys(identity, [
		"settlement_id",
		"authority_profile_id",
		"allocation_index",
		"request_id",
		"request_digest",
	]):
		return _failure("Settlement identity does not match its strict root.")
	if not character_before["item_stacks"] is Dictionary:
		return _failure("Current item stack registry is invalid.")
	if not _has_exact_keys(command, [
		"play_session_identity",
		"command_id",
		"expected_character_revision",
		"expected_inventory_revision",
		"interaction_id",
		"confirmed_experience_cap_loss",
	]):
		return _failure("Delivery command does not match its strict root.")
	if not _has_exact_keys(plan, [
		"rules_hash",
		"quest_before",
		"inventory_before",
		"inputs",
		"progress_before",
		"qigong_before",
		"experience",
	]):
		return _failure("Frozen delivery plan does not match its strict root.")
	if not _validate_settlement_identity(identity):
		return _failure("Settlement identity is invalid.")

	var character_id: Variant = character_before["character_id"]
	var play_session_identity: Variant = command["play_session_identity"]
	if not _has_exact_keys(play_session_identity, ["character_id"]):
		return _failure("Play session identity does not match its strict projection.")
	if (
		typeof(character_id) != TYPE_STRING
		or character_id.strip_edges().is_empty()
		or not play_session_identity is Dictionary
		or play_session_identity.get("character_id") != character_id
		or typeof(command["command_id"]) != TYPE_STRING
		or command.get("command_id") is not String
		or command["command_id"].strip_edges().is_empty()
		or command.get("interaction_id") is not String
		or command["interaction_id"].strip_edges().is_empty()
		or typeof(command["confirmed_experience_cap_loss"]) != TYPE_BOOL
		or not _is_hash(plan.get("rules_hash"))
	):
		return _failure("Delivery command or frozen rules identity is invalid.")
	var character_revision: Variant = character_before["revision"]
	var inventory_revision: Variant = character_before["inventory_revision"]
	if (
		not _is_safe_integer(character_revision, 0, MAX_SAFE_INTEGER - 1)
		or not _is_safe_integer(inventory_revision, 0, MAX_SAFE_INTEGER - 1)
		or command["expected_character_revision"] != character_revision
		or command["expected_inventory_revision"] != inventory_revision
	):
		return _failure("Delivery command revisions do not match current character state.")
	if (
		plan["quest_before"] != character_before["quest"]
		or plan["inventory_before"] != character_before["inventory"]
		or plan["progress_before"] != character_before["progress"]
		or plan["qigong_before"] != character_before["qigong"]
	):
		return _failure("Frozen delivery plan does not match current character state.")
	if not plan["inputs"] is Array or not plan["experience"] is Dictionary:
		return _failure("Frozen delivery plan is incomplete.")
	if not _has_exact_keys(plan["experience"], ["base_award", "credited", "discarded"]):
		return _failure("Frozen experience result does not match its strict projection.")
	if not existing_object_ids is Array:
		return _failure("Existing object identities are required.")
	if not source_flows_before is Array or not experience_records is Array or not award_records is Array:
		return _failure("Complete source and progression histories are required.")
	if not _validate_reserved_plan(plan, command):
		return _failure("Frozen delivery plan does not satisfy its reserved-event rules.")

	var materials: Dictionary = MATERIAL_AGGREGATION.validate_inputs(
		plan["quest_before"],
		plan["inventory_before"],
		character_before["item_stacks"],
		character_id,
		source_flows_before,
		plan["inputs"]
	)
	if not materials.get("ok", false):
		return materials
	if materials["inputs"] != plan["inputs"]:
		return _failure("Frozen delivery inputs changed.")
	var progression: Dictionary = EXPERIENCE_AWARD.calculate_delivery_after(
		materials,
		plan["progress_before"],
		plan["qigong_before"],
		command["confirmed_experience_cap_loss"],
		experience_records,
		award_records
	)
	if not progression.get("ok", false):
		return progression
	if plan["experience"] != progression["experience"]:
		return _failure("Frozen experience result does not match its progression inputs.")

	var settlement_id: String = identity["settlement_id"]
	var consume_receipt_id: String = settlement_id + ":stack:consume"
	var mint_receipt_id: String = settlement_id + ":stack:mint"
	var reward_stack_id: String = _stack_id(settlement_id, character_id, 0)
	if reward_stack_id.is_empty():
		return _failure("Could not derive the recommendation stack identity.")
	var occupied_ids: Dictionary = {}
	for object_id: Variant in existing_object_ids:
		if typeof(object_id) != TYPE_STRING or object_id.strip_edges().is_empty():
			return _failure("Existing object identity is invalid.")
		if occupied_ids.has(object_id):
			return _failure("Existing object identity is duplicated.")
		occupied_ids[object_id] = true
	for stack_id: Variant in character_before["item_stacks"].keys():
		if typeof(stack_id) != TYPE_STRING or stack_id.strip_edges().is_empty():
			return _failure("Current stack registry identity is invalid.")
		if occupied_ids.has(stack_id):
			return _failure("Current stack identity is duplicated in the global object registry.")
		occupied_ids[stack_id] = true
	if occupied_ids.has(reward_stack_id):
		return _failure("Deterministic reward stack identity already exists.")

	var consume_inputs: Array[Dictionary] = []
	var consumptions: Array[Dictionary] = []
	var consumed_stack_ids: Dictionary = {}
	for input_index: int in range(materials["inputs"].size()):
		var input_value: Dictionary = materials["inputs"][input_index]
		var stack: Dictionary = input_value["stack"]
		var stack_id: String = stack["stack_id"]
		if consumed_stack_ids.has(stack_id):
			return _failure("Delivery input stack is duplicated.")
		consumed_stack_ids[stack_id] = true
		consume_inputs.append(input_value["previous_output"].duplicate(true))
		consumptions.append({
			"input_index": input_index,
			"quantity": stack["quantity"],
			"reason": "quest_delivery",
		})

	var reward_stack: Dictionary = {
		"stack_id": reward_stack_id,
		"item_id": RECOMMENDATION_ITEM_ID,
		"binding": "character",
		"quest_scope": null,
		"quantity": 1,
		"revision": 0,
		"origin_receipt_id": mint_receipt_id,
	}
	for receipt_id: String in [consume_receipt_id, mint_receipt_id]:
		if occupied_ids.has(receipt_id):
			return _failure("Delivery flow receipt identity already exists.")
		occupied_ids[receipt_id] = true
	var stack_flows: Array[Dictionary] = [
		{
			"receipt_id": consume_receipt_id,
			"inputs": consume_inputs,
			"outputs": [],
			"consumptions": consumptions,
			"mint_authorization": null,
		},
		{
			"receipt_id": mint_receipt_id,
			"inputs": [],
			"outputs": [{
				"character_id": character_id,
				"stack": reward_stack,
				"contributions": [],
				"custody": {"kind": "held"},
			}],
			"consumptions": [],
			"mint_authorization": {
				"kind": "quest_reward",
				"authority_receipt_id": settlement_id,
			},
		},
	]

	var inventory_result: Dictionary = _build_inventory_after(
		plan["inventory_before"],
		consumed_stack_ids,
		reward_stack_id
	)
	if not inventory_result.get("ok", false):
		return inventory_result
	var item_stacks_after: Dictionary = character_before["item_stacks"].duplicate(true)
	var inventory_stack_ids: Dictionary = {}
	for slot_value: Dictionary in plan["inventory_before"]["slots"]:
		inventory_stack_ids[slot_value["target_id"]] = true
	if inventory_stack_ids.size() != character_before["item_stacks"].size():
		return _failure("Carried stack registry contains an unplaced or duplicate stack.")
	for stack_id: String in character_before["item_stacks"]:
		if not inventory_stack_ids.has(stack_id):
			return _failure("Carried stack registry contains an unplaced stack.")
	for stack_id: String in consumed_stack_ids:
		if not item_stacks_after.has(stack_id):
			return _failure("Consumed delivery stack is missing from the current registry.")
		item_stacks_after.erase(stack_id)
	item_stacks_after[reward_stack_id] = reward_stack
	var final_stack_ids: Dictionary = {}
	for slot_value: Dictionary in inventory_result["inventory_after"]["slots"]:
		var target_id: String = slot_value["target_id"]
		if final_stack_ids.has(target_id):
			return _failure("Committed inventory references a stack more than once.")
		final_stack_ids[target_id] = true
	if final_stack_ids.size() != item_stacks_after.size():
		return _failure("Committed inventory and carried stack registry disagree.")
	for stack_id: String in item_stacks_after:
		if not final_stack_ids.has(stack_id):
			return _failure("Committed stack registry has an unplaced stack.")

	var quest_after: Dictionary = plan["quest_before"].duplicate(true)
	quest_after["state"] = "delivered"
	quest_after["completion_receipt_id_or_null"] = settlement_id
	var committed_event: Dictionary = {
		"phase": "committed",
		"identity": identity.duplicate(true),
		"command": command.duplicate(true),
		"plan": plan.duplicate(true),
		"character_revision_after": int(character_revision) + 1,
		"inventory_revision_after": int(inventory_revision) + 1,
		"quest_after": quest_after,
		"stack_flows": stack_flows,
		"progress_after": progression["progress_after"],
		"qigong_after": progression["qigong_after"],
	}
	if not _validate_commit_candidate(
		committed_event,
		character_before,
		inventory_result["inventory_after"],
		item_stacks_after,
		progression
	):
		return _failure("Committed recommendation delivery candidate failed its owner checks.")
	return {
		"ok": true,
		"event_after": committed_event,
		"inventory_after": inventory_result["inventory_after"],
		"item_stacks_after": item_stacks_after,
	}


static func _validate_commit_candidate(
	event: Dictionary,
	character_before: Dictionary,
	inventory_after: Dictionary,
	item_stacks_after: Dictionary,
	progression: Dictionary
) -> bool:
	if (
		not _has_exact_keys(event, [
			"phase",
			"identity",
			"command",
			"plan",
			"character_revision_after",
			"inventory_revision_after",
			"quest_after",
			"stack_flows",
			"progress_after",
			"qigong_after",
		])
		or not _has_exact_keys(event["quest_after"], [
			"state",
			"attempt_id_or_null",
			"completion_receipt_id_or_null",
		])
		or not _has_exact_keys(event["progress_after"], [
			"total_xp",
			"hp",
			"mana",
			"stamina",
			"completed_rank",
			"route",
		])
		or not _has_exact_keys(event["qigong_after"], [
			"covered_level",
			"level_award_spans",
			"qigong_unallocated",
			"allocations",
			"learned_manuals",
			"anti_allocations",
			"anti_cooldowns",
			"ascension_unallocated",
		])
		or
		event.get("phase") != "committed"
		or event.get("character_revision_after") != int(character_before["revision"]) + 1
		or event.get("inventory_revision_after") != int(character_before["inventory_revision"]) + 1
		or event.get("progress_after") != progression.get("progress_after")
		or event.get("qigong_after") != progression.get("qigong_after")
		or not event.get("quest_after") is Dictionary
		or event["quest_after"].get("state") != "delivered"
		or not event["quest_after"].get("completion_receipt_id_or_null") is String
		or not event.get("stack_flows") is Array
		or event["stack_flows"].size() != 2
		or not inventory_after.get("slots") is Array
		or not _has_exact_keys(inventory_after, ["expansion_level", "slots"])
	):
		return false
	var quest_before: Dictionary = event["plan"]["quest_before"]
	if (
		event["quest_after"].get("attempt_id_or_null") != quest_before.get("attempt_id_or_null")
		or event["quest_after"].get("completion_receipt_id_or_null")
			!= event["identity"].get("settlement_id")
		or event["progress_after"].get("completed_rank") != 1
		or event["progress_after"].get("route") != "unselected"
		or event["progress_after"].get("hp", 0) < 1
		or event["progress_after"].get("total_xp", 0) < 6352000
		or event["progress_after"].get("total_xp", 0) > 371126840985
		or not _is_safe_integer(
			event.get("character_revision_after"),
			1,
			MAX_SAFE_INTEGER
		)
		or not _is_safe_integer(
			event.get("inventory_revision_after"),
			1,
			MAX_SAFE_INTEGER
		)
	):
		return false
	var consume: Dictionary = event["stack_flows"][0]
	var mint: Dictionary = event["stack_flows"][1]
	var completion_receipt: String = event["quest_after"]["completion_receipt_id_or_null"]
	if (
		not _has_exact_keys(consume, [
			"receipt_id",
			"inputs",
			"outputs",
			"consumptions",
			"mint_authorization",
		])
		or not _has_exact_keys(mint, [
			"receipt_id",
			"inputs",
			"outputs",
			"consumptions",
			"mint_authorization",
		])
		or
		consume.get("receipt_id") != completion_receipt + ":stack:consume"
		or consume.get("outputs") != []
		or consume.get("mint_authorization") != null
		or mint.get("receipt_id") != completion_receipt + ":stack:mint"
		or mint.get("inputs") != []
		or mint.get("consumptions") != []
		or mint.get("mint_authorization") != {
			"kind": "quest_reward",
			"authority_receipt_id": completion_receipt,
		}
		or not mint.get("outputs") is Array
		or mint["outputs"].size() != 1
	):
		return false
	var reward_output: Dictionary = mint["outputs"][0]
	if not _has_exact_keys(reward_output, [
		"character_id",
		"stack",
		"contributions",
		"custody",
	]):
		return false
	var reward_stack: Dictionary = reward_output.get("stack", {})
	if (
		not _has_exact_keys(reward_stack, [
			"stack_id",
			"item_id",
			"binding",
			"quest_scope",
			"quantity",
			"revision",
			"origin_receipt_id",
		])
		or reward_output.get("character_id") != character_before["character_id"]
		or
		reward_stack.get("item_id") != RECOMMENDATION_ITEM_ID
		or reward_stack.get("binding") != "character"
		or reward_stack.get("quest_scope") != null
		or reward_stack.get("quantity") != 1
		or reward_stack.get("revision") != 0
		or reward_stack.get("origin_receipt_id") != mint["receipt_id"]
		or reward_output.get("contributions") != []
		or reward_output.get("custody") != {"kind": "held"}
	):
		return false
	if (
		typeof(event["command"].get("confirmed_experience_cap_loss")) != TYPE_BOOL
		or (event["plan"]["experience"]["discarded"] > 0)
			!= event["command"]["confirmed_experience_cap_loss"]
		or not _has_exact_keys(event["plan"]["experience"], [
			"base_award",
			"credited",
			"discarded",
		])
		or event["plan"]["experience"]["base_award"] != 11000
		or event["plan"]["experience"]["credited"] + event["plan"]["experience"]["discarded"]
			!= 11000
	):
		return false
	var flow_input_keys: Dictionary = {}
	var flow_input_count: int = 0
	for input_value: Dictionary in consume.get("inputs", []):
		if not _has_exact_keys(input_value, ["receipt_id", "output_index"]):
			return false
		var key: String = JSON.stringify(input_value)
		if flow_input_keys.has(key):
			return false
		flow_input_keys[key] = true
		flow_input_count += 1
	var consumption_keys: Dictionary = {}
	var consumed_quantity: Dictionary = {}
	for consumption: Dictionary in consume.get("consumptions", []):
		if not _has_exact_keys(consumption, ["input_index", "quantity", "reason"]):
			return false
		if (
			not _is_safe_integer(consumption.get("input_index"), 0, flow_input_count - 1)
			or not _is_safe_integer(consumption.get("quantity"), 1, 10)
			or consumption.get("reason") != "quest_delivery"
		):
			return false
		var input_index: int = int(consumption["input_index"])
		if consumption_keys.has(input_index):
			return false
		consumption_keys[input_index] = true
		consumed_quantity[input_index] = consumption["quantity"]
	if (
		flow_input_count < 2
		or flow_input_count > 15
		or consumption_keys.size() != flow_input_count
		or event["plan"]["inputs"].size() != flow_input_count
	):
		return false
	for index: int in range(flow_input_count):
		var planned_input: Dictionary = event["plan"]["inputs"][index]
		if (
			not _has_exact_keys(planned_input, ["previous_output", "stack"])
			or not _has_exact_keys(planned_input["previous_output"], ["receipt_id", "output_index"])
			or not _has_exact_keys(planned_input["stack"], [
				"stack_id",
				"item_id",
				"binding",
				"quest_scope",
				"quantity",
				"revision",
				"origin_receipt_id",
			])
			or
			consume["inputs"][index] != planned_input["previous_output"]
			or int(consumed_quantity[index]) != int(planned_input["stack"]["quantity"])
		):
			return false
		if (
			planned_input["previous_output"]["receipt_id"]
				!= planned_input["stack"]["origin_receipt_id"]
			or planned_input["previous_output"]["output_index"] != 0
			or planned_input["stack"]["binding"] != "character"
			or not planned_input["stack"]["quest_scope"] is Dictionary
			or planned_input["stack"]["quest_scope"].get("quest_id") != QUEST_ID
			or planned_input["stack"]["quest_scope"].get("attempt_id")
				!= event["quest_after"]["attempt_id_or_null"]
		):
			return false
	var output_stack_id: Variant = reward_stack.get("stack_id")
	if (
		typeof(output_stack_id) != TYPE_STRING
		or item_stacks_after.get(output_stack_id) != reward_stack
		or reward_stack.get("origin_receipt_id") != mint.get("receipt_id")
		or mint["outputs"][0]["character_id"] != character_before["character_id"]
	):
		return false
	var inventory_ids: Dictionary = {}
	for slot_value: Dictionary in inventory_after["slots"]:
		if not _has_exact_keys(slot_value, ["slot_index", "kind", "target_id"]):
			return false
		if (
			not _is_safe_integer(slot_value.get("slot_index"), 0, 199)
			or slot_value.get("kind") != "stack"
			or typeof(slot_value.get("target_id")) != TYPE_STRING
		):
			return false
		var target_id: String = slot_value["target_id"]
		if inventory_ids.has(target_id):
			return false
		inventory_ids[target_id] = true
	if inventory_ids.size() != item_stacks_after.size():
		return false
	for stack_id: String in item_stacks_after:
		if not inventory_ids.has(stack_id):
			return false
	return true


static func _validate_reserved_plan(plan: Dictionary, command: Dictionary) -> bool:
	var quest: Variant = plan.get("quest_before")
	var progress: Variant = plan.get("progress_before")
	var inventory: Variant = plan.get("inventory_before")
	var experience: Variant = plan.get("experience")
	if (
		not quest is Dictionary
		or not _has_exact_keys(quest, [
			"state",
			"attempt_id_or_null",
			"completion_receipt_id_or_null",
		])
		or quest.get("state") != "in_progress"
		or typeof(quest.get("attempt_id_or_null")) != TYPE_STRING
		or quest["attempt_id_or_null"].strip_edges().is_empty()
		or quest.get("completion_receipt_id_or_null") != null
		or not progress is Dictionary
		or not _has_exact_keys(progress, [
			"total_xp",
			"hp",
			"mana",
			"stamina",
			"completed_rank",
			"route",
		])
		or not _is_safe_integer(progress.get("total_xp"), 6341000, 371126840985)
		or not _is_safe_integer(progress.get("hp"), 1, MAX_SAFE_INTEGER)
		or not _is_safe_integer(progress.get("mana"), 0, MAX_SAFE_INTEGER)
		or not _is_safe_integer(progress.get("stamina"), 0, 100)
		or progress.get("completed_rank") != 1
		or progress.get("route") != "unselected"
		or not inventory is Dictionary
		or not _has_exact_keys(inventory, ["expansion_level", "slots"])
		or not _is_safe_integer(inventory.get("expansion_level"), 0, 7)
		or not inventory.get("slots") is Array
		or not experience is Dictionary
		or not _has_exact_keys(experience, ["base_award", "credited", "discarded"])
		or experience.get("base_award") != 11000
		or not _is_safe_integer(experience.get("credited"), 0, 11000)
		or not _is_safe_integer(experience.get("discarded"), 0, 11000)
		or experience["credited"] + experience["discarded"] != 11000
		or typeof(command.get("confirmed_experience_cap_loss")) != TYPE_BOOL
		or (experience["discarded"] > 0) != command["confirmed_experience_cap_loss"]
	):
		return false
	return (
		_is_safe_integer(
			command.get("expected_character_revision"),
			0,
			MAX_SAFE_INTEGER - 1
		)
		and _is_safe_integer(
			command.get("expected_inventory_revision"),
			0,
			MAX_SAFE_INTEGER - 1
		)
	)


static func _build_inventory_after(
	inventory_before: Variant,
	consumed_stack_ids: Dictionary,
	reward_stack_id: String
) -> Dictionary:
	if not inventory_before is Dictionary or inventory_before.size() != 2:
		return _failure("Inventory does not match its strict root.")
	if (
		not _is_safe_integer(inventory_before.get("expansion_level"), 0, 7)
		or not inventory_before.get("slots") is Array
		or inventory_before["slots"].size() > 200
	):
		return _failure("Inventory layout is invalid.")
	var inventory_after: Dictionary = inventory_before.duplicate(true)
	var retained_slots: Array[Dictionary] = []
	var occupied_indices: Dictionary = {}
	var removed_stack_count: int = 0
	for slot_value: Variant in inventory_before["slots"]:
		if not slot_value is Dictionary or slot_value.size() != 3:
			return _failure("Inventory slot is invalid.")
		var slot_index: Variant = slot_value.get("slot_index")
		var target_id: Variant = slot_value.get("target_id")
		if (
			not _is_safe_integer(slot_index, 0, 199)
			or slot_value.get("kind") != "stack"
			or typeof(target_id) != TYPE_STRING
			or occupied_indices.has(slot_index)
		):
			return _failure("Inventory slot index or target is invalid.")
		if consumed_stack_ids.has(target_id):
			removed_stack_count += 1
		else:
			occupied_indices[slot_index] = true
			retained_slots.append(slot_value.duplicate(true))
	if removed_stack_count != consumed_stack_ids.size():
		return _failure("A consumed delivery stack is not in the carried inventory.")
	var free_slot: int = -1
	for slot_index: int in range(200):
		if not occupied_indices.has(slot_index):
			free_slot = slot_index
			break
	if free_slot < 0:
		return _failure("Inventory has no slot for the recommendation.")
	retained_slots.append({
		"slot_index": free_slot,
		"kind": "stack",
		"target_id": reward_stack_id,
	})
	retained_slots.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return int(left["slot_index"]) < int(right["slot_index"])
	)
	inventory_after["slots"] = retained_slots
	return {
		"ok": true,
		"inventory_after": inventory_after,
	}


static func _validate_settlement_identity(identity: Dictionary) -> bool:
	var authority_profile_id: Variant = identity["authority_profile_id"]
	var allocation_index: Variant = identity["allocation_index"]
	var settlement_id: Variant = identity["settlement_id"]
	if (
		typeof(authority_profile_id) != TYPE_STRING
		or authority_profile_id.strip_edges().is_empty()
		or typeof(allocation_index) != TYPE_INT
		or not _is_safe_integer(allocation_index, 0, MAX_SAFE_INTEGER - 1)
		or typeof(settlement_id) != TYPE_STRING
		or not settlement_id.begins_with("settlement:")
		or settlement_id.length() != 75
		or not _is_lower_hex(settlement_id.substr(11))
		or typeof(identity["request_id"]) != TYPE_STRING
		or identity["request_id"].strip_edges().is_empty()
		or not _is_hash(identity["request_digest"])
	):
		return false
	var canonical_identity: Dictionary = CANONICAL_JSON.sha256([
		authority_profile_id,
		int(allocation_index),
	])
	return (
		canonical_identity.get("ok", false)
		and settlement_id == "settlement:" + canonical_identity.get("digest", "")
	)


static func _stack_id(settlement_id: String, character_id: String, ordinal: int) -> String:
	var digest: Dictionary = CANONICAL_JSON.sha256([
		settlement_id,
		character_id,
		ordinal,
	])
	if not digest.get("ok", false):
		return ""
	return "stack:" + digest["digest"]


static func _has_exact_keys(value: Dictionary, expected_keys: Array[String]) -> bool:
	if value.size() != expected_keys.size():
		return false
	for key: String in expected_keys:
		if not value.has(key):
			return false
	return true


static func _is_hash(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and value.length() == 64 and _is_lower_hex(value)


static func _is_lower_hex(value: String) -> bool:
	for index: int in range(value.length()):
		var codepoint: int = value.unicode_at(index)
		if not (codepoint in range(48, 58) or codepoint in range(97, 103)):
			return false
	return true


static func _is_safe_integer(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number == floor(number) and number >= minimum and number <= maximum


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
	}
