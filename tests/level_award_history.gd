extends SceneTree

const LEVEL_AWARD_HISTORY: Script = preload("res://scripts/gameplay/level_award_history.gd")


func _initialize() -> void:
	var table: Dictionary = _load_contract("res://docs/contracts/升级发点.v1.json")
	if table.is_empty():
		return
	var records: Array = table["records"]
	if not _assert(records.size() == 180, "Level award contract does not have 180 rows."):
		return

	var initial: Dictionary = {
		"covered_level": 34,
		"level_award_spans": [{
			"first_level": 2,
			"last_level": 34,
			"kind": "legacy_import_skip",
			"award_rule_version": 1,
			"qigong_points_awarded": 0,
			"ascension_points_awarded": 0,
		}],
	}
	var before_ascension: Dictionary = LEVEL_AWARD_HISTORY.append_experience_awards(
		initial,
		34,
		38,
		5,
		records
	)
	if not _assert(
		before_ascension.get("ok") == true,
		"Pre-ascension award calculation failed: %s" % before_ascension
	):
		return
	if not _assert(
		before_ascension["awards"] == {"qigong_points": 7, "ascension_points": 0},
		"Pre-ascension crossing did not sum newly reached levels 35 through 38."
	):
		return
	var first_span: Dictionary = before_ascension["history_after"]["level_award_spans"][1]
	if not _assert(
		first_span["first_level"] == 35
			and first_span["last_level"] == 38
			and first_span["kind"] == "before_first_ascension",
		"Pre-ascension history span is incorrect."
	):
		return

	var after_ascension: Dictionary = LEVEL_AWARD_HISTORY.append_experience_awards(
		before_ascension["history_after"],
		38,
		40,
		6,
		records
	)
	if not _assert(after_ascension.get("ok") == true, "Post-ascension award calculation failed."):
		return
	if not _assert(
		after_ascension["awards"] == {"qigong_points": 6, "ascension_points": 2},
		"Post-ascension crossing did not use the pre-transaction rank."
	):
		return

	var replay: Dictionary = LEVEL_AWARD_HISTORY.append_experience_awards(
		after_ascension["history_after"],
		38,
		40,
		6,
		records
	)
	if not _assert(
		replay.get("ok") == true
			and replay["awards"] == {"qigong_points": 0, "ascension_points": 0}
			and replay["history_after"] == after_ascension["history_after"],
		"Already covered levels were awarded again."
	):
		return

	var bad_history: Dictionary = after_ascension["history_after"].duplicate(true)
	bad_history["level_award_spans"][0]["last_level"] = 37
	var rejected: Dictionary = LEVEL_AWARD_HISTORY.append_experience_awards(
		bad_history,
		38,
		40,
		6,
		records
	)
	if not _assert(rejected.get("ok") == false, "Malformed span coverage was accepted."):
		return

	print("Level award history tests passed.")
	quit(0)


func _load_contract(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Level award contract is missing.")
		return {}
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		_fail("Level award contract is invalid JSON.")
		return {}
	return json.data


func _assert(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
