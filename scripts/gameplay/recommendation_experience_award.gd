extends RefCounted

const BASE_AWARD: int = 11000
const MAX_TOTAL_XP: int = 371126840985
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
