extends RefCounted

const QUEST_ID: String = "ref_QREF-63791-016"
const AXE_ITEM_ID: String = "recommendation_bandit_axe"
const PROOF_ITEM_ID: String = "recommendation_bandit_proof"
const MAX_SAFE_INTEGER: int = 9007199254740991


static func validate_inputs(
	quest_before: Variant,
	inventory_before: Variant,
	item_stacks_before: Variant,
	character_id: Variant,
	source_flows_before: Variant,
	inputs: Variant
) -> Dictionary:
	if not quest_before is Dictionary:
		return _failure("Quest state must be an object.")
	if (
		quest_before.size() != 3
		or not quest_before.has("state")
		or not quest_before.has("attempt_id_or_null")
		or not quest_before.has("completion_receipt_id_or_null")
	):
		return _failure("Recommendation quest state does not match its strict root.")
	if quest_before["state"] != "in_progress":
		return _failure("Recommendation quest must be in progress.")
	var attempt_id: Variant = quest_before["attempt_id_or_null"]
	if typeof(attempt_id) != TYPE_STRING or attempt_id.strip_edges().is_empty():
		return _failure("Recommendation quest attempt is invalid.")
	if quest_before["completion_receipt_id_or_null"] != null:
		return _failure("A completed recommendation quest cannot accept delivery inputs.")

	if not inventory_before is Dictionary or not inventory_before.get("slots") is Array:
		return _failure("Inventory slots are required.")
	if not item_stacks_before is Dictionary:
		return _failure("Item stack registry is required.")
	if typeof(character_id) != TYPE_STRING or character_id.strip_edges().is_empty():
		return _failure("Character identity is invalid.")
	if not inputs is Array:
		return _failure("Delivery inputs must be an array.")
	var source_index: Dictionary = _index_source_flows(source_flows_before)
	if not source_index.get("ok", false):
		return source_index

	var ordered_slots: Array[Dictionary] = []
	var seen_slot_indices: Dictionary = {}
	for slot_value: Variant in inventory_before["slots"]:
		if not slot_value is Dictionary:
			return _failure("Inventory slot is invalid.")
		var slot_index: Variant = slot_value.get("slot_index")
		if not _is_safe_integer(slot_index, 0, 199):
			return _failure("Inventory slot index is invalid.")
		if seen_slot_indices.has(slot_index):
			return _failure("Inventory slot index is duplicated.")
		seen_slot_indices[slot_index] = true
		if slot_value.get("kind") != "stack":
			return _failure("Inventory slot kind is unsupported.")
		var target_id: Variant = slot_value.get("target_id")
		if typeof(target_id) != TYPE_STRING or target_id.is_empty():
			return _failure("Inventory stack reference is invalid.")
		ordered_slots.append(slot_value)
	ordered_slots.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return int(left["slot_index"]) < int(right["slot_index"])
	)

	var expected_stack_ids: Array[String] = []
	var totals: Dictionary = {
		AXE_ITEM_ID: 0,
		PROOF_ITEM_ID: 0,
	}
	var seen_stack_ids: Dictionary = {}
	for slot: Dictionary in ordered_slots:
		var stack_id: String = slot["target_id"]
		if seen_stack_ids.has(stack_id):
			return _failure("Inventory stack is referenced more than once.")
		seen_stack_ids[stack_id] = true
		if not item_stacks_before.has(stack_id):
			return _failure("Inventory references a missing stack.")
		var stack: Variant = item_stacks_before[stack_id]
		if not stack is Dictionary or stack.get("stack_id") != stack_id:
			return _failure("Inventory stack identity does not match its registry key.")

		var item_id: Variant = stack.get("item_id")
		if item_id != AXE_ITEM_ID and item_id != PROOF_ITEM_ID:
			continue
		if stack.get("binding") != "character":
			return _failure("Recommendation materials must be character-bound.")
		var quest_scope: Variant = stack.get("quest_scope")
		if (
			not quest_scope is Dictionary
			or quest_scope.size() != 2
			or quest_scope.get("quest_id") != QUEST_ID
			or typeof(quest_scope.get("attempt_id")) != TYPE_STRING
			or quest_scope["attempt_id"].strip_edges().is_empty()
		):
			return _failure("Recommendation material quest scope is invalid.")
		var quantity: Variant = stack.get("quantity")
		if not _is_safe_integer(quantity, 1, 9999):
			return _failure("Recommendation material quantity is invalid.")
		if quest_scope["attempt_id"] != attempt_id:
			continue
		if int(totals[item_id]) > MAX_SAFE_INTEGER - int(quantity):
			return _failure("Current-attempt material total exceeds the safe integer range.")

		expected_stack_ids.append(stack_id)
		totals[item_id] = int(totals[item_id]) + int(quantity)

	if totals[AXE_ITEM_ID] != 10 or totals[PROOF_ITEM_ID] != 5:
		return _failure("Current-attempt materials must total exactly 10 axes and 5 proofs.")
	if inputs.size() != expected_stack_ids.size():
		return _failure("Delivery inputs do not cover every current-attempt material stack.")

	var seen_input_ids: Dictionary = {}
	for input_index: int in range(inputs.size()):
		var input_value: Variant = inputs[input_index]
		if not input_value is Dictionary or input_value.size() != 2:
			return _failure("Delivery material input is invalid.")
		var input_stack: Variant = input_value.get("stack")
		var previous_output: Variant = input_value.get("previous_output")
		if not input_stack is Dictionary or not previous_output is Dictionary:
			return _failure("Delivery material input is missing its stack or source reference.")
		if previous_output.size() != 2:
			return _failure("Delivery material source reference is invalid.")
		var source_receipt_id: Variant = previous_output.get("receipt_id")
		if typeof(source_receipt_id) != TYPE_STRING or source_receipt_id.strip_edges().is_empty():
			return _failure("Delivery material source receipt is invalid.")
		if source_receipt_id != input_stack.get("origin_receipt_id"):
			return _failure("Delivery material source receipt does not match its current stack.")
		if not _is_safe_integer(previous_output.get("output_index"), 0, 0):
			return _failure("Delivery material source output index is invalid.")

		var expected_stack_id: String = expected_stack_ids[input_index]
		if seen_input_ids.has(expected_stack_id):
			return _failure("Delivery material stack is duplicated.")
		seen_input_ids[expected_stack_id] = true
		if input_stack.get("stack_id") != expected_stack_id:
			return _failure("Delivery inputs are not in inventory slot order.")
		if input_stack != item_stacks_before[expected_stack_id]:
			return _failure("Delivery input does not equal the current inventory stack.")
		var source_check: Dictionary = _validate_current_source(
			input_stack,
			previous_output,
			character_id,
			source_index["flows_by_receipt"],
			source_index["consumed_outputs"]
		)
		if not source_check.get("ok", false):
			return source_check

	return {
		"ok": true,
		"stack_ids": expected_stack_ids,
		"totals": totals,
		"inputs": inputs.duplicate(true),
		"quest_before": quest_before.duplicate(true),
	}


static func _index_source_flows(source_flows: Variant) -> Dictionary:
	if not source_flows is Array:
		return _failure("Stack-flow history list is required.")

	var flows_by_receipt: Dictionary = {}
	var consumed_outputs: Dictionary = {}
	var dependencies: Dictionary = {}
	var dependents: Dictionary = {}
	var dependency_counts: Dictionary = {}
	for flow_value: Variant in source_flows:
		if not flow_value is Dictionary or flow_value.size() != 5:
			return _failure("Stack-flow history entry is invalid.")
		var receipt_id: Variant = flow_value.get("receipt_id")
		if (
			typeof(receipt_id) != TYPE_STRING
			or receipt_id.strip_edges().is_empty()
			or not flow_value.get("inputs") is Array
			or not flow_value.get("outputs") is Array
			or not flow_value.get("consumptions") is Array
			or not flow_value.has("mint_authorization")
			or flows_by_receipt.has(receipt_id)
		):
			return _failure("Stack-flow history identity or shape is invalid.")
		flows_by_receipt[receipt_id] = flow_value
		dependencies[receipt_id] = {}
		dependents[receipt_id] = []
		dependency_counts[receipt_id] = 0

	for flow_value: Dictionary in flows_by_receipt.values():
		var receipt_id: String = flow_value["receipt_id"]
		for input_value: Variant in flow_value["inputs"]:
			if not input_value is Dictionary or input_value.size() != 2:
				return _failure("Stack-flow history input is invalid.")
			var source_receipt_id: Variant = input_value.get("receipt_id")
			var output_index: Variant = input_value.get("output_index")
			if (
				typeof(source_receipt_id) != TYPE_STRING
				or source_receipt_id.strip_edges().is_empty()
				or not flows_by_receipt.has(source_receipt_id)
				or not _is_safe_integer(output_index, 0, MAX_SAFE_INTEGER)
			):
				return _failure("Stack-flow history has an unresolved input.")
			var source_flow: Dictionary = flows_by_receipt[source_receipt_id]
			if int(output_index) >= source_flow["outputs"].size():
				return _failure("Stack-flow history input output index is out of range.")
			var output_key: String = _output_key(source_receipt_id, int(output_index))
			if consumed_outputs.has(output_key):
				return _failure("A stack-flow output is consumed more than once.")
			consumed_outputs[output_key] = true
			if not dependencies[receipt_id].has(source_receipt_id):
				dependencies[receipt_id][source_receipt_id] = true
				dependents[source_receipt_id].append(receipt_id)
				dependency_counts[receipt_id] = int(dependency_counts[receipt_id]) + 1

	var ready_receipts: Array[String] = []
	for receipt_id: String in dependency_counts:
		if dependency_counts[receipt_id] == 0:
			ready_receipts.append(receipt_id)
	var visited_count: int = 0
	while not ready_receipts.is_empty():
		var receipt_id: String = ready_receipts.pop_back()
		visited_count += 1
		for dependent_receipt: String in dependents[receipt_id]:
			dependency_counts[dependent_receipt] = int(dependency_counts[dependent_receipt]) - 1
			if dependency_counts[dependent_receipt] == 0:
				ready_receipts.append(dependent_receipt)
	if visited_count != flows_by_receipt.size():
		return _failure("Stack-flow history contains a dependency cycle.")

	return {
		"ok": true,
		"flows_by_receipt": flows_by_receipt,
		"consumed_outputs": consumed_outputs,
	}


static func _validate_current_source(
	stack: Dictionary,
	previous_output: Dictionary,
	character_id: String,
	flows_by_receipt: Dictionary,
	consumed_outputs: Dictionary
) -> Dictionary:
	var receipt_id: String = previous_output["receipt_id"]
	var output_index: int = int(previous_output["output_index"])
	if receipt_id != stack.get("origin_receipt_id"):
		return _failure("Delivery material source receipt does not match its current stack.")
	if output_index != 0:
		return _failure("Delivery material source output index is invalid.")
	var output_key: String = _output_key(receipt_id, output_index)
	if consumed_outputs.has(output_key):
		return _failure("Delivery material source output has already been consumed.")
	if not flows_by_receipt.has(receipt_id):
		return _failure("Delivery material source receipt is missing from stack-flow history.")

	var source_flow: Dictionary = flows_by_receipt[receipt_id]
	var outputs: Array = source_flow["outputs"]
	if outputs.size() != 1:
		return _failure("Recommendation material source flow must have one output.")
	var source_output: Variant = outputs[output_index]
	if not source_output is Dictionary or source_output.size() != 4:
		return _failure("Delivery material source output is invalid.")
	if (
		source_output.get("character_id") != character_id
		or source_output.get("stack") != stack
		or source_output.get("custody") != {"kind": "held"}
		or not source_output.get("contributions") is Array
	):
		return _failure("Delivery material source output does not match the current held stack.")
	return {"ok": true}


static func _output_key(receipt_id: String, output_index: int) -> String:
	return JSON.stringify([receipt_id, output_index])


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
