extends SceneTree

const EXPERIENCE_AWARD: Script = preload("res://scripts/gameplay/recommendation_experience_award.gd")
const BASE_AWARD: int = 11000
const MAX_TOTAL_XP: int = 371126840985


func _initialize() -> void:
	var exact_cap: Dictionary = EXPERIENCE_AWARD.calculate_award(
		MAX_TOTAL_XP - BASE_AWARD,
		false
	)
	if not _require(exact_cap.get("ok", false), "An exact-cap award was rejected."):
		return
	if not _require(
		exact_cap["experience"] == {
			"base_award": BASE_AWARD,
			"credited": BASE_AWARD,
			"discarded": 0,
		}
			and exact_cap["total_xp_after"] == MAX_TOTAL_XP,
		"An exact-cap award was not preserved in full."
	):
		return

	var one_xp_lost: Dictionary = EXPERIENCE_AWARD.calculate_award(
		MAX_TOTAL_XP - BASE_AWARD + 1,
		true
	)
	if not _require(
		one_xp_lost.get("ok", false)
			and one_xp_lost["experience"]["credited"] == BASE_AWARD - 1
			and one_xp_lost["experience"]["discarded"] == 1
			and one_xp_lost["total_xp_after"] == MAX_TOTAL_XP,
		"A one-XP cap loss was not calculated correctly."
	):
		return
	if not _require(
		not EXPERIENCE_AWARD.calculate_award(
			MAX_TOTAL_XP - BASE_AWARD + 1,
			false
		).get("ok", false),
		"An unconfirmed cap loss was accepted."
	):
		return

	var at_cap: Dictionary = EXPERIENCE_AWARD.calculate_award(MAX_TOTAL_XP, true)
	if not _require(
		at_cap.get("ok", false)
			and at_cap["experience"]["credited"] == 0
			and at_cap["experience"]["discarded"] == BASE_AWARD
			and at_cap["total_xp_after"] == MAX_TOTAL_XP,
		"A full-cap award did not discard the complete overflow."
	):
		return
	if not _require(
		not EXPERIENCE_AWARD.calculate_award(MAX_TOTAL_XP, false).get("ok", false),
		"A full-cap award without explicit confirmation was accepted."
	):
		return

	var experience_records: Array = _load_contract_records(
		"res://docs/contracts/等级经验.v1.json"
	)
	var award_records: Array = _load_contract_records("res://docs/contracts/升级发点.v1.json")
	if not _require(
		experience_records.size() == 180 and award_records.size() == 180,
		"Progression contracts must each contain 180 level records."
	):
		return
	var level_34_history: Dictionary = {
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
	var level_35_threshold: int = int(experience_records[34]["minimum_total_xp"])
	var crossed_35: Dictionary = EXPERIENCE_AWARD.calculate_transaction(
		level_35_threshold - 5000,
		false,
		0,
		level_34_history,
		experience_records,
		award_records
	)
	if not _require(
		crossed_35.get("ok", false)
			and crossed_35["level_before"] == 34
			and crossed_35["level_after"] == 35
			and crossed_35["level_awards"] == {
				"qigong_points": 1,
				"ascension_points": 0,
			}
			and crossed_35["history_after"]["covered_level"] == 35,
		"An experience transaction crossing into level 35 was not applied atomically."
	):
		return

	var delivery_materials: Dictionary = {
		"ok": true,
		"stack_ids": ["axe_0", "proof_0"],
		"inputs": [
			{
				"previous_output": {"receipt_id": "source_axe_0", "output_index": 0},
				"stack": {
					"stack_id": "axe_0",
					"item_id": "recommendation_bandit_axe",
					"binding": "character",
					"quest_scope": {
						"quest_id": "ref_QREF-63791-016",
						"attempt_id": "attempt-001",
					},
					"quantity": 10,
					"origin_receipt_id": "source_axe_0",
				},
			},
			{
				"previous_output": {"receipt_id": "source_proof_0", "output_index": 0},
				"stack": {
					"stack_id": "proof_0",
					"item_id": "recommendation_bandit_proof",
					"binding": "character",
					"quest_scope": {
						"quest_id": "ref_QREF-63791-016",
						"attempt_id": "attempt-001",
					},
					"quantity": 5,
					"origin_receipt_id": "source_proof_0",
				},
			},
		],
		"totals": {
			"recommendation_bandit_axe": 10,
			"recommendation_bandit_proof": 5,
		},
		"quest_before": {
			"state": "in_progress",
			"attempt_id_or_null": "attempt-001",
			"completion_receipt_id_or_null": null,
		},
	}
	var delivery_progress: Dictionary = {
		"total_xp": level_35_threshold,
		"hp": 100,
		"mana": 100,
		"stamina": 100,
		"completed_rank": 1,
		"route": "unselected",
	}
	var delivery_qigong: Dictionary = {
		"covered_level": crossed_35["history_after"]["covered_level"],
		"level_award_spans": crossed_35["history_after"]["level_award_spans"],
		"qigong_unallocated": 4,
		"allocations": {},
		"learned_manuals": [],
		"anti_allocations": {},
		"anti_cooldowns": {},
		"ascension_unallocated": 0,
	}
	var delivery: Dictionary = EXPERIENCE_AWARD.calculate_delivery_after(
		delivery_materials,
		delivery_progress,
		delivery_qigong,
		false,
		experience_records,
		award_records
	)
	if not _require(
		delivery.get("ok", false)
			and delivery["experience"]["base_award"] == BASE_AWARD
			and delivery["progress_after"]["total_xp"]
				== delivery_progress["total_xp"] + BASE_AWARD
			and delivery["qigong_after"]["qigong_unallocated"]
				== delivery_qigong["qigong_unallocated"]
					+ delivery["level_awards"]["qigong_points"]
			and delivery["qigong_after"]["covered_level"] == delivery["level_after"]
			and delivery["qigong_after"]["allocations"] == delivery_qigong["allocations"],
		"Recommendation delivery did not produce one consistent progress and qigong result."
	):
		return
	if not _require(
		not EXPERIENCE_AWARD.calculate_delivery_after(
			{"ok": true, "stack_ids": [], "totals": {}},
			delivery_progress,
			delivery_qigong,
			false,
			experience_records,
			award_records
		).get("ok", false)
			and not EXPERIENCE_AWARD.calculate_delivery_after(
				delivery_materials,
				delivery_progress.merged({"route": "righteous"}, true),
				delivery_qigong,
				false,
				experience_records,
				award_records
			).get("ok", false)
			and not EXPERIENCE_AWARD.calculate_delivery_after(
				delivery_materials.merged({"stack_ids": ["axe_0", "axe_0"]}, true),
				delivery_progress,
				delivery_qigong,
				false,
				experience_records,
				award_records
			).get("ok", false)
			and not EXPERIENCE_AWARD.calculate_delivery_after(
				delivery_materials,
				delivery_progress.merged({"hp": 0}, true),
				delivery_qigong,
				false,
				experience_records,
				award_records
			).get("ok", false),
		"Invalid material totals, a dead character, or a selected route were accepted."
	):
		return

	var full_qigong_pool: Dictionary = delivery_qigong.duplicate(true)
	full_qigong_pool["covered_level"] = 179
	full_qigong_pool["level_award_spans"] = [{
		"first_level": 2,
		"last_level": 179,
		"kind": "legacy_import_skip",
		"award_rule_version": 1,
		"qigong_points_awarded": 0,
		"ascension_points_awarded": 0,
	}]
	full_qigong_pool["qigong_unallocated"] = 9007199254740991
	var final_delivery_progress: Dictionary = delivery_progress.duplicate(true)
	final_delivery_progress["total_xp"] = MAX_TOTAL_XP - 5
	if not _require(
		not EXPERIENCE_AWARD.calculate_delivery_after(
			delivery_materials,
			final_delivery_progress,
			full_qigong_pool,
			true,
			experience_records,
			award_records
		).get("ok", false),
		"A qigong pool overflow was accepted."
	):
		return

	var level_179_history: Dictionary = {
		"covered_level": 179,
		"level_award_spans": [{
			"first_level": 2,
			"last_level": 179,
			"kind": "legacy_import_skip",
			"award_rule_version": 1,
			"qigong_points_awarded": 0,
			"ascension_points_awarded": 0,
		}],
	}
	var crossed_180: Dictionary = EXPERIENCE_AWARD.calculate_transaction(
		MAX_TOTAL_XP - 5,
		true,
		6,
		level_179_history,
		experience_records,
		award_records
	)
	if not _require(
		crossed_180.get("ok", false)
			and crossed_180["experience"]["credited"] == 5
			and crossed_180["experience"]["discarded"] == BASE_AWARD - 5
			and crossed_180["level_before"] == 179
			and crossed_180["level_after"] == 180
			and crossed_180["level_awards"] == {
				"qigong_points": 3,
				"ascension_points": 1,
			},
		"A capped transaction crossing into level 180 was not calculated correctly."
	):
		return

	for invalid_total: Variant in [-1, 1.5, MAX_TOTAL_XP + 1]:
		if not _require(
			not EXPERIENCE_AWARD.calculate_award(invalid_total, false).get("ok", false),
			"An invalid total experience value was accepted: %s" % invalid_total
		):
			return

	print("Recommendation experience award checks passed.")
	quit(0)


func _load_contract_records(path: String) -> Array:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Progression contract is missing: %s" % path)
		return []
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		_fail("Progression contract is invalid JSON: %s" % path)
		return []
	return json.data.get("records", [])


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
