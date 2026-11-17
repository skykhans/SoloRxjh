extends SceneTree

const DELIVERY: Script = preload("res://scripts/gameplay/recommendation_delivery_transaction.gd")
const EXPERIENCE: Script = preload("res://scripts/gameplay/recommendation_experience_award.gd")
const CANONICAL_JSON: Script = preload("res://scripts/canonical_json.gd")
const MAX_TOTAL_XP: int = 371126840985


func _initialize() -> void:
	var settlement_digest: Dictionary = CANONICAL_JSON.sha256(["profile-001", 2])
	if not _require(
		settlement_digest.get("ok", false)
			and settlement_digest.get("digest")
				== "31b51d36268ff2995f0de16c598bcb7065da6f5c6d120723fd1ffc13df88b866"
			and DELIVERY._stack_id(
				"settlement:31b51d36268ff2995f0de16c598bcb7065da6f5c6d120723fd1ffc13df88b866",
				"character-001",
				0
			) == "stack:dfd1e4c9c7f19f47a02f90693e56645d0e36533d9a334fde61d925645b15cdc1",
		"Canonical settlement or reward stack identity changed."
	):
		return
	var fixture: Dictionary = _make_fixture()
	var candidate: Dictionary = _build(fixture)
	if not _require(candidate.get("ok", false), "A valid reserved delivery was rejected.") or not candidate.get("ok", false):
		return
	var event_after: Dictionary = candidate["event_after"]
	var flows: Array = event_after["stack_flows"]
	if not _validate_delivery_event(event_after):
		return
	if not _require(
		event_after["phase"] == "committed"
			and event_after["character_revision_after"] == 8
			and event_after["inventory_revision_after"] == 12
			and event_after["quest_after"]["state"] == "delivered"
			and flows.size() == 2
			and flows[0]["receipt_id"] == "settlement:%s:stack:consume" % fixture["settlement_hash"]
			and flows[1]["receipt_id"] == "settlement:%s:stack:mint" % fixture["settlement_hash"],
		"Committed delivery identity, revisions, quest, or flow order is invalid."
	):
		return
	var final_slots: Array = candidate["inventory_after"]["slots"]
	var reward_slot: Dictionary = {}
	for slot_value: Dictionary in final_slots:
		if slot_value["target_id"] == flows[1]["outputs"][0]["stack"]["stack_id"]:
			reward_slot = slot_value
			break
	if not _require(
		final_slots.size() == 199
			and reward_slot.get("slot_index") == 0
			and reward_slot["target_id"] == flows[1]["outputs"][0]["stack"]["stack_id"]
			and candidate["item_stacks_after"].size() == 199
			and flows[0]["inputs"].size() == 2
			and flows[0]["consumptions"].size() == 2
			and flows[1]["outputs"][0]["stack"]["item_id"] == "adv02_recommendation"
			and flows[1]["outputs"][0]["stack"]["quantity"] == 1,
		"Delivery did not consume materials and reuse the lowest released inventory slot."
	):
		return

	var collision: Dictionary = _build(fixture, [DELIVERY._stack_id(
		"settlement:" + fixture["settlement_hash"],
		"character-001",
		0,
	)])
	if not _require(not collision.get("ok", false), "A deterministic stack ID collision was accepted."):
		return

	var stale: Dictionary = fixture.duplicate(true)
	stale["character"]["revision"] += 1
	if not _require(not _build(stale).get("ok", false), "A stale character revision was accepted."):
		return

	var fractional_identity: Dictionary = fixture.duplicate(true)
	fractional_identity["reserved"]["identity"]["allocation_index"] = 2.0
	if not _require(
		not _build(fractional_identity).get("ok", false),
		"A non-integer allocation index was accepted."
	):
		return

	var changed_plan: Dictionary = fixture.duplicate(true)
	changed_plan["reserved"]["plan"]["inputs"][0]["stack"]["quantity"] = 2
	if not _require(
		not _build(changed_plan).get("ok", false),
		"A frozen plan that differs from the current stack was accepted."
	):
		return
	var changed_quest: Dictionary = fixture.duplicate(true)
	changed_quest["reserved"]["plan"]["quest_before"]["attempt_id_or_null"] = "another-attempt"
	if not _require(
		not _build(changed_quest).get("ok", false),
		"A frozen plan for another quest attempt was accepted."
	):
		return
	var wrong_cap_confirmation: Dictionary = fixture.duplicate(true)
	wrong_cap_confirmation["reserved"]["command"]["confirmed_experience_cap_loss"] = true
	if not _require(
		not _build(wrong_cap_confirmation).get("ok", false),
		"Cap-loss confirmation without discarded experience was accepted."
	):
		return
	var extra_reserved_field: Dictionary = fixture.duplicate(true)
	extra_reserved_field["reserved"]["unexpected"] = true
	if not _require(
		not _build(extra_reserved_field).get("ok", false),
		"An unexpected reserved-event field was accepted."
	):
		return
	var altered_source: Dictionary = fixture.duplicate(true)
	altered_source["source_flows"][0]["outputs"][0]["character_id"] = "another-character"
	if not _require(
		not _build(altered_source).get("ok", false),
		"A material sourced for another character was accepted."
	):
		return
	var altered_candidate: Dictionary = candidate.duplicate(true)
	altered_candidate["event_after"]["stack_flows"][0]["inputs"][0]["output_index"] = 1
	var altered_event: Dictionary = altered_candidate["event_after"]
	if not _require(
		not DELIVERY._validate_commit_candidate(
			altered_event,
			fixture["character"],
			altered_candidate["inventory_after"],
			altered_candidate["item_stacks_after"],
			{
				"progress_after": altered_event["progress_after"],
				"qigong_after": altered_event["qigong_after"],
			}
		),
		"A committed flow that differs from its frozen source was accepted."
	):
		return
	var invalid_existing_id: Dictionary = _build(fixture, [""])
	if not _require(
		not invalid_existing_id.get("ok", false),
		"An invalid object identity in the global registry was accepted."
	):
		return
	var unplaced_stack: Dictionary = fixture.duplicate(true)
	unplaced_stack["character"]["item_stacks"]["orphan-stack"] = {
		"stack_id": "orphan-stack",
		"item_id": "ordinary_consumable",
		"binding": "character",
		"quest_scope": null,
		"quantity": 1,
		"revision": 0,
		"origin_receipt_id": "orphan-source",
	}
	if not _require(
		not _build(unplaced_stack).get("ok", false),
		"An unplaced carried stack was accepted."
	):
		return

	print("Recommendation delivery transaction checks passed.")
	quit(0)


func _build(fixture: Dictionary, existing_ids: Array = []) -> Dictionary:
	return DELIVERY.build_committed_candidate(
		fixture["reserved"],
		fixture["character"],
		fixture["source_flows"],
		existing_ids,
		fixture["experience_records"],
		fixture["award_records"]
	)


func _make_fixture() -> Dictionary:
	var settlement_result: Dictionary = CANONICAL_JSON.sha256(["profile-001", 2])
	var settlement_hash: String = settlement_result["digest"]
	var settlement_id: String = "settlement:" + settlement_hash
	var quest: Dictionary = {
		"state": "in_progress",
		"attempt_id_or_null": "attempt-001",
		"completion_receipt_id_or_null": null,
	}
	var progress: Dictionary = {
		"total_xp": 6352000,
		"hp": 100,
		"mana": 100,
		"stamina": 100,
		"completed_rank": 1,
		"route": "unselected",
	}
	var experience_records: Array = _load_contract_records("res://docs/contracts/等级经验.v1.json")
	var award_records: Array = _load_contract_records("res://docs/contracts/升级发点.v1.json")
	var qigong: Dictionary = {
		"covered_level": 35,
		"level_award_spans": [{
			"first_level": 2,
			"last_level": 35,
			"kind": "legacy_import_skip",
			"award_rule_version": 1,
			"qigong_points_awarded": 0,
			"ascension_points_awarded": 0,
		}],
		"qigong_unallocated": 0,
		"allocations": {},
		"learned_manuals": [],
		"anti_allocations": {},
		"anti_cooldowns": {},
		"ascension_unallocated": 0,
	}
	var stacks: Dictionary = {}
	var slots: Array[Dictionary] = []
	var inputs: Array[Dictionary] = []
	var source_flows: Array[Dictionary] = []
	var stack_index: int = 0
	for item: Dictionary in [
		{"item_id": "recommendation_bandit_axe", "quantity": 10},
		{"item_id": "recommendation_bandit_proof", "quantity": 5},
	]:
		var stack_id: String = "material-%d" % stack_index
		var source_receipt: String = "source-%d" % stack_index
		var stack: Dictionary = {
			"stack_id": stack_id,
			"item_id": item["item_id"],
			"binding": "character",
			"quest_scope": {
				"quest_id": "ref_QREF-63791-016",
				"attempt_id": "attempt-001",
			},
			"quantity": item["quantity"],
			"revision": 0,
			"origin_receipt_id": source_receipt,
		}
		stacks[stack_id] = stack
		var slot: Dictionary = {"slot_index": stack_index, "kind": "stack", "target_id": stack_id}
		slots.append(slot)
		inputs.append({
			"previous_output": {"receipt_id": source_receipt, "output_index": 0},
			"stack": stack.duplicate(true),
		})
		source_flows.append({
			"receipt_id": source_receipt,
			"inputs": [],
			"outputs": [{
				"character_id": "character-001",
				"stack": stack.duplicate(true),
				"contributions": [],
				"custody": {"kind": "held"},
			}],
			"consumptions": [],
			"mint_authorization": {
				"kind": "loot",
				"authority_receipt_id": source_receipt,
			},
		})
		stack_index += 1

	var full_slots: Array[Dictionary] = []
	for slot_index: int in range(200):
		var stack_id: String = "material-%d" % slot_index
		full_slots.append({
			"slot_index": slot_index,
			"kind": "stack",
			"target_id": stack_id,
		})
		if slot_index < 2:
			continue
		var stack: Dictionary = {
			"stack_id": stack_id,
			"item_id": "ordinary_consumable",
			"binding": "character",
			"quest_scope": null,
			"quantity": 1,
			"revision": 0,
			"origin_receipt_id": "untracked-%d" % slot_index,
		}
		stacks[stack_id] = stack
		source_flows.append({
			"receipt_id": "untracked-%d" % slot_index,
			"inputs": [],
			"outputs": [{
				"character_id": "character-001",
				"stack": stack,
				"contributions": [],
				"custody": {"kind": "held"},
			}],
			"consumptions": [],
			"mint_authorization": null,
		})
	var inventory: Dictionary = {"expansion_level": 0, "slots": full_slots}
	var award: Dictionary = EXPERIENCE.calculate_delivery_after(
		{
			"ok": true,
			"stack_ids": ["material-0", "material-1"],
			"totals": {
				"recommendation_bandit_axe": 10,
				"recommendation_bandit_proof": 5,
			},
			"inputs": inputs,
			"quest_before": quest,
		},
		progress,
		qigong,
		false,
		experience_records,
		award_records
	)
	var reserved: Dictionary = {
		"phase": "reserved",
		"identity": {
			"settlement_id": settlement_id,
			"authority_profile_id": "profile-001",
			"allocation_index": 2,
			"request_id": "request-001",
			"request_digest": "b".repeat(64),
		},
		"command": {
			"play_session_identity": {"character_id": "character-001"},
			"command_id": "command-001",
			"expected_character_revision": 7,
			"expected_inventory_revision": 11,
			"interaction_id": "interaction-001",
			"confirmed_experience_cap_loss": false,
		},
		"plan": {
			"rules_hash": "a".repeat(64),
			"quest_before": quest,
			"inventory_before": inventory,
			"inputs": inputs,
			"progress_before": progress,
			"qigong_before": qigong,
			"experience": award.get("experience", {}),
		},
	}
	var character: Dictionary = {
		"character_id": "character-001",
		"revision": 7,
		"inventory_revision": 11,
		"quest": quest,
		"inventory": inventory,
		"item_stacks": stacks,
		"progress": progress,
		"qigong": qigong,
	}
	return {
		"reserved": reserved,
		"character": character,
		"source_flows": source_flows,
		"experience_records": experience_records,
		"award_records": award_records,
		"settlement_hash": settlement_hash,
	}


func _load_contract_records(path: String) -> Array:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Progression contract is missing: %s" % path)
		quit(1)
		return []
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_error("Progression contract is invalid JSON: %s" % path)
		quit(1)
		return []
	return json.data.get("records", [])


func _validate_delivery_event(event: Dictionary) -> bool:
	var schema_file: FileAccess = FileAccess.open(
		"res://docs/contracts/泫勃推荐书交付事件.schema.json",
		FileAccess.READ
	)
	if schema_file == null:
		return _require(false, "Recommendation delivery schema is missing.")
	var schema_json: JSON = JSON.new()
	if schema_json.parse(schema_file.get_as_text()) != OK:
		return _require(false, "Recommendation delivery schema is invalid JSON.")
	var event_json: JSON = JSON.new()
	if event_json.parse(JSON.stringify(event)) != OK or not event_json.data is Dictionary:
		return _require(false, "Committed recommendation event cannot be serialized.")
	return _require(
		event_json.data["phase"] == "committed"
			and event_json.data.size() == 10
			and event_json.data.has("identity")
			and event_json.data.has("command")
			and event_json.data.has("plan")
			and event_json.data.has("character_revision_after")
			and event_json.data.has("inventory_revision_after")
			and event_json.data.has("quest_after")
			and event_json.data.has("progress_after")
			and event_json.data.has("qigong_after")
			and event_json.data["stack_flows"].size() == 2
			and schema_json.data["$id"] == "urn:solorxjh:hyunbo-recommendation-delivery-event:v1",
		"Committed recommendation event or schema identity is invalid."
	)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false
