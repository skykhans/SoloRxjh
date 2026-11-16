extends SceneTree

const AGGREGATION: Script = preload("res://scripts/gameplay/recommendation_material_aggregation.gd")
const QUEST_ID: String = "ref_QREF-63791-016"
const AXE_ITEM_ID: String = "recommendation_bandit_axe"
const PROOF_ITEM_ID: String = "recommendation_bandit_proof"


func _initialize() -> void:
	var valid_case: Dictionary = _make_case([3, 3, 4], [2, 3])
	var result: Dictionary = AGGREGATION.validate_inputs(
		valid_case["quest"],
		valid_case["inventory"],
		valid_case["stacks"],
		valid_case["inputs"]
	)
	if not _require(result.get("ok", false), "Split current-attempt stacks were rejected."):
		return
	if not _require(
		result["totals"] == {AXE_ITEM_ID: 10, PROOF_ITEM_ID: 5},
		"Material totals were not aggregated by item ID."
	):
		return

	var under_case: Dictionary = _make_case([3, 3, 3], [2, 3])
	if not _require(
		not _validate(under_case).get("ok", false),
		"An under-counted material set was accepted."
	):
		return

	var over_case: Dictionary = _make_case([5, 5, 1], [2, 3])
	if not _require(
		not _validate(over_case).get("ok", false),
		"An over-counted material set was accepted."
	):
		return

	var missing_case: Dictionary = _make_case([3, 3, 4], [2, 3])
	missing_case["inputs"].remove_at(1)
	if not _require(
		not _validate(missing_case).get("ok", false),
		"A missing held stack was accepted."
	):
		return

	var order_case: Dictionary = _make_case([3, 3, 4], [2, 3])
	var first_input: Dictionary = order_case["inputs"][0]
	order_case["inputs"][0] = order_case["inputs"][1]
	order_case["inputs"][1] = first_input
	if not _require(
		not _validate(order_case).get("ok", false),
		"Inputs outside inventory slot order were accepted."
	):
		return

	var reference_case: Dictionary = _make_case([3, 3, 4], [2, 3])
	reference_case["inventory"]["slots"][4]["target_id"] = "axe_00"
	if not _require(
		not _validate(reference_case).get("ok", false),
		"A stack referenced by multiple inventory slots was accepted."
	):
		return

	var scope_case: Dictionary = _make_case([3, 3, 4], [2, 3])
	scope_case["stacks"]["axe_00"]["quest_scope"]["world_id"] = "world-unexpected"
	scope_case["inputs"][0]["stack"]["quest_scope"]["world_id"] = "world-unexpected"
	if not _require(
		not _validate(scope_case).get("ok", false),
		"A material stack with an extended quest scope was accepted."
	):
		return

	print("Recommendation material aggregation checks passed.")
	quit(0)


func _validate(test_case: Dictionary) -> Dictionary:
	return AGGREGATION.validate_inputs(
		test_case["quest"],
		test_case["inventory"],
		test_case["stacks"],
		test_case["inputs"]
	)


func _make_case(axe_quantities: Array[int], proof_quantities: Array[int]) -> Dictionary:
	var attempt_id: String = "attempt-001"
	var quest: Dictionary = {
		"state": "in_progress",
		"attempt_id": attempt_id,
		"completion_receipt_id_or_null": null,
	}
	var slots: Array[Dictionary] = []
	var stacks: Dictionary = {}
	var inputs: Array[Dictionary] = []
	var slot_index: int = 0

	for item: Dictionary in [
		{"item_id": AXE_ITEM_ID, "quantities": axe_quantities, "prefix": "axe"},
		{"item_id": PROOF_ITEM_ID, "quantities": proof_quantities, "prefix": "proof"},
	]:
		for quantity_index: int in range(item["quantities"].size()):
			var stack_id: String = "%s_%02d" % [item["prefix"], quantity_index]
			var stack: Dictionary = {
				"stack_id": stack_id,
				"item_id": item["item_id"],
				"binding": "character",
				"quest_scope": {
					"quest_id": QUEST_ID,
					"attempt_id": attempt_id,
				},
				"quantity": item["quantities"][quantity_index],
				"revision": 0,
				"origin_receipt_id": "source_%s" % stack_id,
			}
			stacks[stack_id] = stack
			slots.append({
				"slot_index": slot_index,
				"kind": "stack",
				"target_id": stack_id,
			})
			inputs.append({
				"previous_output": {
					"receipt_id": "source_%s" % stack_id,
					"output_index": 0,
				},
				"stack": stack.duplicate(true),
			})
			slot_index += 1

	var older_attempt_stack: Dictionary = {
		"stack_id": "axe_old",
		"item_id": AXE_ITEM_ID,
		"binding": "character",
		"quest_scope": {
			"quest_id": QUEST_ID,
			"attempt_id": "attempt-old",
		},
		"quantity": 1,
		"revision": 0,
		"origin_receipt_id": "source_axe_old",
	}
	stacks["axe_old"] = older_attempt_stack
	slots.append({
		"slot_index": slot_index,
		"kind": "stack",
		"target_id": "axe_old",
	})

	return {
		"quest": quest,
		"inventory": {
			"expansion_level": 0,
			"slots": slots,
		},
		"stacks": stacks,
		"inputs": inputs,
	}


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false
