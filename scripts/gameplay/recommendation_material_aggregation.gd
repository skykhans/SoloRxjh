extends RefCounted

const QUEST_ID: String = "ref_QREF-63791-016"
const AXE_ITEM_ID: String = "recommendation_bandit_axe"
const PROOF_ITEM_ID: String = "recommendation_bandit_proof"
const MAX_SAFE_INTEGER: int = 9007199254740991


static func validate_inputs(
	quest_before: Variant,
	inventory_before: Variant,
	item_stacks_before: Variant,
	inputs: Variant
) -> Dictionary:
	if not quest_before is Dictionary:
		return _failure("Quest state must be an object.")
	if quest_before.get("state") != "in_progress":
		return _failure("Recommendation quest must be in progress.")
	var attempt_id: Variant = quest_before.get("attempt_id")
	if typeof(attempt_id) != TYPE_STRING or attempt_id.is_empty():
		return _failure("Recommendation quest attempt is invalid.")

	if not inventory_before is Dictionary or not inventory_before.get("slots") is Array:
		return _failure("Inventory slots are required.")
	if not item_stacks_before is Dictionary:
		return _failure("Item stack registry is required.")
	if not inputs is Array:
		return _failure("Delivery inputs must be an array.")

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
		var quest_scope: Variant = stack.get("quest_scope")
		if not quest_scope is Dictionary:
			continue
		if quest_scope.get("quest_id") != QUEST_ID or quest_scope.get("attempt_id") != attempt_id:
			continue
		if quest_scope.size() != 2:
			return _failure("Current-attempt material quest scope is invalid.")
		if stack.get("binding") != "character":
			return _failure("Current-attempt materials must be character-bound.")
		var quantity: Variant = stack.get("quantity")
		if not _is_safe_integer(quantity, 1, 9999):
			return _failure("Current-attempt material quantity is invalid.")
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
		if not _is_safe_integer(previous_output.get("output_index"), 0, MAX_SAFE_INTEGER):
			return _failure("Delivery material source output index is invalid.")

		var expected_stack_id: String = expected_stack_ids[input_index]
		if seen_input_ids.has(expected_stack_id):
			return _failure("Delivery material stack is duplicated.")
		seen_input_ids[expected_stack_id] = true
		if input_stack.get("stack_id") != expected_stack_id:
			return _failure("Delivery inputs are not in inventory slot order.")
		if input_stack != item_stacks_before[expected_stack_id]:
			return _failure("Delivery input does not equal the current inventory stack.")

	return {
		"ok": true,
		"stack_ids": expected_stack_ids,
		"totals": totals,
	}


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
