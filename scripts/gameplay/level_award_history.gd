extends RefCounted

const MAX_SAFE_INTEGER: int = 9007199254740991
const MAX_LEVEL: int = 180
const AWARD_RULE_VERSION: int = 1
const SPAN_KINDS: Array[String] = [
	"before_first_ascension",
	"after_first_ascension",
	"configuration_skip",
	"legacy_import_skip",
]


static func append_experience_awards(
	history_before: Variant,
	level_before: Variant,
	level_after: Variant,
	rank_before: Variant,
	level_records: Variant
) -> Dictionary:
	if not history_before is Dictionary or history_before.size() != 2:
		return _failure("Level award history must contain exactly two fields.")
	if not level_records is Array or level_records.size() != MAX_LEVEL:
		return _failure("Level award records must cover levels 1 through 180.")
	if not _is_safe_integer(history_before.get("covered_level"), 1, MAX_LEVEL):
		return _failure("Covered level is outside the supported range.")
	if not _is_safe_integer(level_before, 1, MAX_LEVEL):
		return _failure("Level before the experience transaction is invalid.")
	if not _is_safe_integer(level_after, 1, MAX_LEVEL):
		return _failure("Level after the experience transaction is invalid.")
	if not _is_safe_integer(rank_before, 0, 12):
		return _failure("Rank before the experience transaction is invalid.")
	if int(level_after) < int(level_before):
		return _failure("Experience transactions cannot reduce the character level.")
	var records_check: Dictionary = _validate_level_records(level_records)
	if not records_check["ok"]:
		return records_check

	var spans_before: Variant = history_before.get("level_award_spans")
	if not spans_before is Array:
		return _failure("Level award spans must be an array.")
	var history_check: Dictionary = _validate_history(
		int(history_before["covered_level"]),
		spans_before,
		level_records
	)
	if not history_check["ok"]:
		return history_check
	var covered_level: int = int(history_before["covered_level"])
	if int(level_before) > covered_level:
		return _failure("Character level exceeds the recorded award coverage.")

	var spans_after: Array = spans_before.duplicate(true)
	var qigong_awarded: int = 0
	var ascension_awarded: int = 0
	var first_new_level: int = covered_level + 1
	var last_new_level: int = int(level_after)
	if first_new_level <= last_new_level:
		var kind: String = (
			"after_first_ascension"
			if int(rank_before) >= 6
			else "before_first_ascension"
		)
		for reached_level: int in range(first_new_level, last_new_level + 1):
			var record: Variant = level_records[reached_level - 1]
			var record_check: Dictionary = _validate_level_record(record, reached_level)
			if not record_check["ok"]:
				return record_check
			qigong_awarded += int(
				record[
					"qigong_points_after_first_ascension"
					if kind == "after_first_ascension"
					else "qigong_points_without_first_ascension"
				]
			)
			if kind == "after_first_ascension":
				ascension_awarded += int(record["ascension_points_after_first_ascension"])
		spans_after.append({
			"first_level": first_new_level,
			"last_level": last_new_level,
			"kind": kind,
			"award_rule_version": AWARD_RULE_VERSION,
			"qigong_points_awarded": qigong_awarded,
			"ascension_points_awarded": ascension_awarded,
		})

	return {
		"ok": true,
		"history_after": {
			"covered_level": maxi(covered_level, last_new_level),
			"level_award_spans": spans_after,
		},
		"awards": {
			"qigong_points": qigong_awarded,
			"ascension_points": ascension_awarded,
		},
	}


static func _validate_history(
	covered_level: int,
	spans: Array,
	level_records: Array
) -> Dictionary:
	if spans.size() > MAX_LEVEL - 1:
		return _failure("Level award history has too many spans.")
	if (covered_level == 1) != spans.is_empty():
		return _failure("Covered level and span count are inconsistent.")

	var next_level: int = 2
	for span_value: Variant in spans:
		if not span_value is Dictionary or span_value.size() != 6:
			return _failure("Level award span has an invalid shape.")
		for field: String in [
			"first_level",
			"last_level",
			"kind",
			"award_rule_version",
			"qigong_points_awarded",
			"ascension_points_awarded",
		]:
			if not span_value.has(field):
				return _failure("Level award span is missing a required field.")
		var first_level: Variant = span_value["first_level"]
		var last_level: Variant = span_value["last_level"]
		var kind: Variant = span_value["kind"]
		if not _is_safe_integer(first_level, 2, MAX_LEVEL):
			return _failure("Level award span start is invalid.")
		if not _is_safe_integer(last_level, 2, MAX_LEVEL):
			return _failure("Level award span end is invalid.")
		if int(first_level) != next_level or int(last_level) < int(first_level):
			return _failure("Level award spans must be contiguous and in order.")
		if int(last_level) > covered_level:
			return _failure("Level award span exceeds the recorded coverage.")
		if typeof(kind) != TYPE_STRING or not SPAN_KINDS.has(kind):
			return _failure("Level award span kind is unsupported.")
		if not _is_safe_integer(
			span_value["award_rule_version"],
			AWARD_RULE_VERSION,
			AWARD_RULE_VERSION
		):
			return _failure("Level award span rule version is unsupported.")
		if not _is_safe_integer(span_value["qigong_points_awarded"], 0, MAX_SAFE_INTEGER):
			return _failure("Level award qigong total is invalid.")
		if not _is_safe_integer(span_value["ascension_points_awarded"], 0, MAX_SAFE_INTEGER):
			return _failure("Level award ascension total is invalid.")

		var expected_qigong: int = 0
		var expected_ascension: int = 0
		for reached_level: int in range(int(first_level), int(last_level) + 1):
			var record: Variant = level_records[reached_level - 1]
			var record_check: Dictionary = _validate_level_record(record, reached_level)
			if not record_check["ok"]:
				return record_check
			if kind == "before_first_ascension":
				expected_qigong += int(record["qigong_points_without_first_ascension"])
			elif kind == "after_first_ascension":
				expected_qigong += int(record["qigong_points_after_first_ascension"])
				expected_ascension += int(record["ascension_points_after_first_ascension"])

		if int(span_value["qigong_points_awarded"]) != expected_qigong:
			return _failure("Level award qigong total does not match the level table.")
		if int(span_value["ascension_points_awarded"]) != expected_ascension:
			return _failure("Level award ascension total does not match the level table.")
		next_level = int(last_level) + 1

	if next_level != covered_level + 1:
		return _failure("Level award spans do not cover the recorded range.")
	return {"ok": true}


static func _validate_level_record(record: Variant, expected_level: int) -> Dictionary:
	if not record is Dictionary or record.size() != 4:
		return _failure("Level award table row has an invalid shape.")
	if record.get("level_reached") != expected_level:
		return _failure("Level award table rows are missing or out of order.")
	for field: String in [
		"qigong_points_without_first_ascension",
		"qigong_points_after_first_ascension",
		"ascension_points_after_first_ascension",
	]:
		if not _is_safe_integer(record.get(field), 0, MAX_SAFE_INTEGER):
			return _failure("Level award table contains an invalid point value.")
	return {"ok": true}


static func _validate_level_records(level_records: Array) -> Dictionary:
	for level_index: int in range(MAX_LEVEL):
		var record_check: Dictionary = _validate_level_record(
			level_records[level_index],
			level_index + 1
		)
		if not record_check["ok"]:
			return record_check
	return {"ok": true}


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
