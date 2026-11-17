extends RefCounted

const BASE_AWARD: int = 11000
const MAX_TOTAL_XP: int = 371126840985
const MAX_SAFE_INTEGER: int = 9007199254740991
const MAX_LEVEL: int = 180
const LEVEL_AWARD_HISTORY: Script = preload("res://scripts/gameplay/level_award_history.gd")


static func calculate_award(total_xp_before: Variant, confirmed_cap_loss: Variant) -> Dictionary:
	if not _is_safe_integer(total_xp_before, 0, MAX_TOTAL_XP):
		return _failure("Total experience is outside the supported range.")
	if typeof(confirmed_cap_loss) != TYPE_BOOL:
		return _failure("Experience cap confirmation must be boolean.")

	var before: int = int(total_xp_before)
	var credited: int = mini(BASE_AWARD, MAX_TOTAL_XP - before)
	var discarded: int = BASE_AWARD - credited
	if (discarded > 0) != confirmed_cap_loss:
		return _failure("Experience cap confirmation does not match the calculated loss.")

	return {
		"ok": true,
		"experience": {
			"base_award": BASE_AWARD,
			"credited": credited,
			"discarded": discarded,
		},
		"total_xp_after": before + credited,
	}


static func calculate_transaction(
	total_xp_before: Variant,
	confirmed_cap_loss: Variant,
	rank_before: Variant,
	history_before: Variant,
	experience_records: Variant,
	award_records: Variant
) -> Dictionary:
	var award: Dictionary = calculate_award(total_xp_before, confirmed_cap_loss)
	if not award["ok"]:
		return award
	if not _is_safe_integer(rank_before, 0, 12):
		return _failure("Rank before the experience transaction is invalid.")
	var experience_table_check: Dictionary = _validate_experience_records(experience_records)
	if not experience_table_check["ok"]:
		return experience_table_check

	var level_before: int = _level_for_total_xp(int(total_xp_before), experience_records)
	var level_after: int = _level_for_total_xp(int(award["total_xp_after"]), experience_records)
	var history_result: Dictionary = LEVEL_AWARD_HISTORY.append_experience_awards(
		history_before,
		level_before,
		level_after,
		int(rank_before),
		award_records
	)
	if not history_result["ok"]:
		return history_result
	award["level_before"] = level_before
	award["level_after"] = level_after
	award["level_awards"] = history_result["awards"]
	award["history_after"] = history_result["history_after"]
	return award


static func calculate_delivery_after(
	material_validation: Variant,
	progress_before: Variant,
	qigong_before: Variant,
	confirmed_cap_loss: Variant,
	experience_records: Variant,
	award_records: Variant
) -> Dictionary:
	if not material_validation is Dictionary or material_validation.size() != 5:
		return _failure("Validated recommendation materials are required.")
	if (
		material_validation.get("ok") != true
		or not material_validation.get("stack_ids") is Array
		or not material_validation.get("totals") is Dictionary
		or not material_validation.get("inputs") is Array
		or material_validation["inputs"].size() != material_validation["stack_ids"].size()
		or not material_validation.get("quest_before") is Dictionary
		or material_validation["stack_ids"].size() < 2
		or material_validation["stack_ids"].size() > 15
	):
		return _failure("Recommendation material totals are invalid.")
	var quest_before: Dictionary = material_validation["quest_before"]
	if (
		quest_before.size() != 3
		or quest_before.get("state") != "in_progress"
		or typeof(quest_before.get("attempt_id_or_null")) != TYPE_STRING
		or quest_before["attempt_id_or_null"].strip_edges().is_empty()
		or quest_before.get("completion_receipt_id_or_null") != null
	):
		return _failure("Recommendation quest state is invalid.")
	var seen_stack_ids: Dictionary = {}
	var input_totals: Dictionary = {
		"recommendation_bandit_axe": 0,
		"recommendation_bandit_proof": 0,
	}
	for input_index: int in range(material_validation["stack_ids"].size()):
		var stack_id: Variant = material_validation["stack_ids"][input_index]
		if typeof(stack_id) != TYPE_STRING or stack_id.strip_edges().is_empty():
			return _failure("Recommendation material stack identity is invalid.")
		if seen_stack_ids.has(stack_id):
			return _failure("Recommendation material stack identity is duplicated.")
		seen_stack_ids[stack_id] = true
		var input_value: Variant = material_validation["inputs"][input_index]
		if not input_value is Dictionary or input_value.size() != 2:
			return _failure("Recommendation material input is invalid.")
		var stack: Variant = input_value.get("stack")
		var previous_output: Variant = input_value.get("previous_output")
		if (
			not stack is Dictionary
			or stack.get("stack_id") != stack_id
			or stack.get("binding") != "character"
			or not stack.get("quest_scope") is Dictionary
			or stack["quest_scope"] != {
				"quest_id": "ref_QREF-63791-016",
				"attempt_id": quest_before["attempt_id_or_null"],
			}
			or not previous_output is Dictionary
			or previous_output.size() != 2
			or previous_output.get("receipt_id") != stack.get("origin_receipt_id")
			or not _is_safe_integer(previous_output.get("output_index"), 0, 0)
		):
			return _failure("Recommendation material input does not match its validated attempt.")
		var item_id: Variant = stack.get("item_id")
		var quantity: Variant = stack.get("quantity")
		if (
			not input_totals.has(item_id)
			or not _is_safe_integer(quantity, 1, 9999)
			or int(input_totals[item_id]) > MAX_SAFE_INTEGER - int(quantity)
		):
			return _failure("Recommendation material quantity is invalid.")
		input_totals[item_id] = int(input_totals[item_id]) + int(quantity)
	if input_totals != {
		"recommendation_bandit_axe": 10,
		"recommendation_bandit_proof": 5,
	} or material_validation["totals"] != input_totals:
		return _failure("Recommendation material totals are invalid.")
	if not progress_before is Dictionary or progress_before.size() != 6:
		return _failure("Character progress must match its strict root.")
	for field: String in [
		"total_xp",
		"hp",
		"mana",
		"stamina",
		"completed_rank",
		"route",
	]:
		if not progress_before.has(field):
			return _failure("Character progress is missing a required field.")
	if (
		not _is_safe_integer(progress_before["total_xp"], 0, MAX_TOTAL_XP)
		or not _is_safe_integer(progress_before["hp"], 1, 9007199254740991)
		or not _is_safe_integer(progress_before["mana"], 0, 9007199254740991)
		or not _is_safe_integer(progress_before["stamina"], 0, 100)
		or progress_before["completed_rank"] != 1
		or progress_before["route"] != "unselected"
	):
		return _failure("Character does not meet recommendation delivery progression requirements.")
	if not qigong_before is Dictionary or qigong_before.size() != 8:
		return _failure("Qigong state must match its strict root.")
	for field: String in [
		"covered_level",
		"level_award_spans",
		"qigong_unallocated",
		"allocations",
		"learned_manuals",
		"anti_allocations",
		"anti_cooldowns",
		"ascension_unallocated",
	]:
		if not qigong_before.has(field):
			return _failure("Qigong state is missing a required field.")
	if (
		not qigong_before["allocations"] is Dictionary
		or not qigong_before["learned_manuals"] is Array
		or not qigong_before["anti_allocations"] is Dictionary
		or not qigong_before["anti_cooldowns"] is Dictionary
		or not _is_safe_integer(
			qigong_before["qigong_unallocated"],
			0,
			MAX_SAFE_INTEGER
		)
		or not _is_safe_integer(
			qigong_before["ascension_unallocated"],
			0,
			MAX_SAFE_INTEGER
		)
	):
		return _failure("Qigong state contains an invalid pool or root.")

	var transaction: Dictionary = calculate_transaction(
		progress_before["total_xp"],
		confirmed_cap_loss,
		progress_before["completed_rank"],
		{
			"covered_level": qigong_before["covered_level"],
			"level_award_spans": qigong_before["level_award_spans"],
		},
		experience_records,
		award_records
	)
	if not transaction.get("ok", false):
		return transaction
	var level_35_xp: int = int(experience_records[34]["minimum_total_xp"])
	if (
		transaction["level_before"] < 35
		or int(progress_before["total_xp"]) < level_35_xp
		or int(qigong_before["covered_level"]) != transaction["level_before"]
	):
		return _failure("Character level and qigong award coverage are inconsistent.")

	var next_qigong_pool: int = (
		int(qigong_before["qigong_unallocated"])
		+ int(transaction["level_awards"]["qigong_points"])
	)
	var next_ascension_pool: int = (
		int(qigong_before["ascension_unallocated"])
		+ int(transaction["level_awards"]["ascension_points"])
	)
	if next_qigong_pool > MAX_SAFE_INTEGER or next_ascension_pool > MAX_SAFE_INTEGER:
		return _failure("Qigong award exceeds the supported pool range.")

	var progress_after: Dictionary = progress_before.duplicate(true)
	progress_after["total_xp"] = transaction["total_xp_after"]
	var qigong_after: Dictionary = qigong_before.duplicate(true)
	qigong_after["covered_level"] = transaction["history_after"]["covered_level"]
	qigong_after["level_award_spans"] = transaction["history_after"]["level_award_spans"]
	qigong_after["qigong_unallocated"] = next_qigong_pool
	qigong_after["ascension_unallocated"] = next_ascension_pool

	return {
		"ok": true,
		"experience": transaction["experience"],
		"level_before": transaction["level_before"],
		"level_after": transaction["level_after"],
		"level_awards": transaction["level_awards"],
		"progress_after": progress_after,
		"qigong_after": qigong_after,
	}


static func _validate_experience_records(records: Variant) -> Dictionary:
	if not records is Array or records.size() != MAX_LEVEL:
		return _failure("Experience records must cover levels 1 through 180.")
	for level_index: int in range(MAX_LEVEL):
		var record: Variant = records[level_index]
		if not record is Dictionary:
			return _failure("Experience table row is invalid.")
		if record.get("level") != level_index + 1:
			return _failure("Experience table rows are missing or out of order.")
		if not _is_safe_integer(record.get("minimum_total_xp"), 0, MAX_TOTAL_XP):
			return _failure("Experience table threshold is invalid.")
		if level_index == 0 and int(record["minimum_total_xp"]) != 0:
			return _failure("Level 1 must start at zero experience.")
		if level_index < MAX_LEVEL - 1:
			if not _is_safe_integer(record.get("xp_to_next_level"), 1, MAX_TOTAL_XP):
				return _failure("Experience cost to the next level is invalid.")
			var next_record: Variant = records[level_index + 1]
			if not next_record is Dictionary:
				return _failure("Experience table row is invalid.")
			var next_minimum: Variant = next_record.get("minimum_total_xp")
			if not _is_safe_integer(next_minimum, 1, MAX_TOTAL_XP):
				return _failure("Next level threshold is invalid.")
			if (
				int(next_minimum) <= int(record["minimum_total_xp"])
				or int(next_minimum) - int(record["minimum_total_xp"])
					!= int(record["xp_to_next_level"])
			):
				return _failure("Experience thresholds and level costs do not match.")
		elif (
			record.get("xp_to_next_level") != null
			or int(record["minimum_total_xp"]) != MAX_TOTAL_XP
		):
			return _failure("Level 180 must be the terminal experience threshold.")
	return {"ok": true}


static func _level_for_total_xp(total_xp: int, records: Array) -> int:
	var level: int = 1
	for level_index: int in range(1, MAX_LEVEL):
		if total_xp < int(records[level_index]["minimum_total_xp"]):
			break
		level = level_index + 1
	return level


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
