extends SceneTree

const CREATION_COMMAND: Script = preload("res://scripts/character_creation_command.gd")
const PROFILE_ID: String = "profile_0123456789abcdef0123456789abcdef"
const OTHER_PROFILE_ID: String = "profile_fedcba9876543210fedcba9876543210"


func _initialize() -> void:
	var command: Dictionary = _valid_command()
	var result: Dictionary = CREATION_COMMAND.identify(command, PROFILE_ID)
	if not _require(result.get("ok", false), "A valid creation command was rejected."):
		return
	var expected_digest: Dictionary = CREATION_COMMAND.CANONICAL_JSON.sha256(command)
	if not _require(
		result["request_id"]
			== "[\"new_character\",\"%s\",\"0123456789abcdef0123456789abcdef\"]" % PROFILE_ID
			and result["request_digest"] == expected_digest["digest"],
		"Creation request identity or digest does not match the canonical command."
	):
		return
	var allocated: Dictionary = _allocated_identity(command, PROFILE_ID, 5)
	var plan: Dictionary = _plan(command, allocated)
	var built_identity: Dictionary = CREATION_COMMAND.build_character_identity(
		command,
		PROFILE_ID,
		allocated,
		plan
	)
	if not _require(
		built_identity.get("ok", false)
			and built_identity["identity"]["character_id"] == plan["character_id"]
			and built_identity["identity"]["name"] == command["name"]
			and built_identity["identity"]["class_id"] == command["class_id"],
		"A valid frozen creation plan did not build its character identity."
	):
		return
	var reserved_result: Dictionary = CREATION_COMMAND.build_reserved_event(
		command,
		PROFILE_ID,
		allocated,
		plan
	)
	if not _require(
		reserved_result.get("ok", false)
			and reserved_result["event"].keys().size() == 4
			and reserved_result["event"]["phase"] == "reserved"
			and reserved_result["event"]["command"] == command,
		"A valid creation request did not produce its strict reserved event."
	):
		return
	var aborted_result: Dictionary = CREATION_COMMAND.build_aborted_event(
		reserved_result["event"],
		PROFILE_ID
	)
	if not _require(
		aborted_result.get("ok", false)
			and aborted_result["event"]["phase"] == "aborted"
			and aborted_result["event"]["reason"] == "user_cancelled"
			and aborted_result["event"]["decision_profile_revision"] == 6
			and aborted_result["event"]["identity"] == allocated
			and aborted_result["event"]["plan"] == plan,
		"A reserved event did not produce its exact user-cancelled decision."
	):
		return
	var already_aborted: Dictionary = CREATION_COMMAND.build_aborted_event(
		aborted_result["event"],
		PROFILE_ID
	)
	if not _require(
		not already_aborted.get("ok", false),
		"A terminal character creation event was aborted again."
	):
		return
	var invalid_reserved: Dictionary = reserved_result["event"].duplicate(true)
	invalid_reserved["identity"]["allocation_index"] = 5.0
	if not _require(
		not CREATION_COMMAND.build_aborted_event(invalid_reserved, PROFILE_ID).get("ok", false),
		"An invalid reserved event was finalized as aborted."
	):
		return
	reserved_result["event"]["command"]["appearance"]["body_type"] = "female"
	if not _require(
		command["appearance"]["body_type"] == "male",
		"A reserved event shares mutable command state with its caller."
	):
		return
	var wrong_authority: Dictionary = allocated.duplicate(true)
	wrong_authority["authority_profile_id"] = OTHER_PROFILE_ID
	var wrong_allocation_index: Dictionary = allocated.duplicate(true)
	wrong_allocation_index["allocation_index"] = 5.0
	var float_random_counter: Dictionary = plan.duplicate(true)
	float_random_counter["random_state"]["next_block"] = 0.0
	var wrong_character_id: Dictionary = plan.duplicate(true)
	wrong_character_id["character_id"] = "character:" + "0".repeat(64)
	var wrong_reservation_revision: Dictionary = plan.duplicate(true)
	wrong_reservation_revision["reservation_profile_revision"] += 1
	for invalid_result: Dictionary in [
		CREATION_COMMAND.build_character_identity(command, PROFILE_ID, wrong_authority, plan),
		CREATION_COMMAND.build_character_identity(command, PROFILE_ID, wrong_allocation_index, plan),
		CREATION_COMMAND.build_character_identity(command, PROFILE_ID, allocated, float_random_counter),
		CREATION_COMMAND.build_character_identity(command, PROFILE_ID, allocated, wrong_character_id),
		CREATION_COMMAND.build_character_identity(command, PROFILE_ID, allocated, wrong_reservation_revision),
	]:
		if not _require(
			not invalid_result.get("ok", false),
			"An identity plan with a mismatched authority, allocation or reservation was accepted."
		):
			return
	if not _require(
		CREATION_COMMAND.identify(command, OTHER_PROFILE_ID)["request_id"]
			!= result["request_id"],
		"Request ID did not include its authority profile."
	):
		return

	var invalid_commands: Array[Dictionary] = []
	var extra_key: Dictionary = command.duplicate(true)
	extra_key["client_revision"] = 2
	invalid_commands.append(extra_key)
	var uppercase_id: Dictionary = command.duplicate(true)
	uppercase_id["command_id"] = "0123456789ABCDEF0123456789ABCDEF"
	invalid_commands.append(uppercase_id)
	var float_revision: Dictionary = command.duplicate(true)
	float_revision["expected_profile_revision"] = 4.0
	invalid_commands.append(float_revision)
	var exhausted_revision: Dictionary = command.duplicate(true)
	exhausted_revision["expected_profile_revision"] = (
		CREATION_COMMAND.MAX_PROFILE_REVISION - 1
	)
	invalid_commands.append(exhausted_revision)
	var decomposed_name: Dictionary = command.duplicate(true)
	decomposed_name["name"] = "e\u0301乙"
	invalid_commands.append(decomposed_name)
	var invalid_appearance: Dictionary = command.duplicate(true)
	invalid_appearance["appearance"]["body_type"] = "female"
	invalid_appearance["class_id"] = "lu_fenglang"
	invalid_commands.append(invalid_appearance)
	for invalid: Dictionary in invalid_commands:
		if not _require(
			not CREATION_COMMAND.identify(invalid, PROFILE_ID).get("ok", false),
			"An invalid creation command was accepted."
		):
			return
	if not _require(
		not CREATION_COMMAND.identify(command, "档案").get("ok", false),
		"An invalid authority profile ID was accepted."
	):
		return
	for invalid_profile_id: String in [
		"profile_0123456789abcdef",
		"profile_0123456789abcdef0123456789abcdeF",
		"other_0123456789abcdef0123456789abcdef",
	]:
		if not _require(
			not CREATION_COMMAND.identify(command, invalid_profile_id).get("ok", false),
			"A profile ID outside the persisted profile identity format was accepted."
		):
			return

	print("Character creation command identity checks passed.")
	quit(0)


func _valid_command() -> Dictionary:
	return {
		"command_id": "0123456789abcdef0123456789abcdef",
		"expected_profile_revision": 4,
		"name": "青竹",
		"class_id": "sword",
		"appearance": {
			"body_type": "male",
			"skin_tone_id": "warm",
			"hairstyle_id": "high_knot",
			"outfit_palette_id": "indigo",
		},
	}


func _allocated_identity(
	command: Dictionary,
	profile_id: String,
	allocation_index: int
) -> Dictionary:
	var command_identity: Dictionary = CREATION_COMMAND.identify(command, profile_id)
	var settlement_digest: Dictionary = CREATION_COMMAND.CANONICAL_JSON.sha256([
		profile_id,
		allocation_index,
	])
	return {
		"settlement_id": "settlement:" + settlement_digest["digest"],
		"authority_profile_id": profile_id,
		"allocation_index": allocation_index,
		"request_id": command_identity["request_id"],
		"request_digest": command_identity["request_digest"],
	}


func _plan(command: Dictionary, allocated: Dictionary) -> Dictionary:
	var character_digest: Dictionary = CREATION_COMMAND.CANONICAL_JSON.sha256([
		"new_character",
		allocated["settlement_id"],
	])
	return {
		"character_id": "character:" + character_digest["digest"],
		"created_at_utc": "2026-11-16T12:34:56Z",
		"random_state": {
			"algorithm": "sha256_counter_53_v1",
			"seed_hex": "a".repeat(64),
			"next_block": 0,
		},
		"rules_hash": "b".repeat(64),
		"reservation_profile_revision": command["expected_profile_revision"] + 1,
		"initial_character_digest": "c".repeat(64),
	}


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false
