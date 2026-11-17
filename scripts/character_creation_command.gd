extends RefCounted

const CANONICAL_JSON: Script = preload("res://scripts/canonical_json.gd")
const IDENTITY_VALIDATOR: Script = preload("res://scripts/character_identity_validator.gd")
const RANDOM_STREAM: Script = preload("res://scripts/gameplay/random_stream.gd")
const MAX_PROFILE_REVISION: int = 9007199254740989
const MAX_ALLOCATION_INDEX: int = 9007199254740990


static func build_character_identity(
	command: Variant,
	authority_profile_id: String,
	settlement_identity: Variant,
	plan: Variant
) -> Dictionary:
	var command_result: Dictionary = identify(command, authority_profile_id)
	if not command_result.get("ok", false):
		return command_result
	if not _has_exact_keys(settlement_identity, [
		"settlement_id",
		"authority_profile_id",
		"allocation_index",
		"request_id",
		"request_digest",
	]):
		return _failure("Allocated settlement identity must match its strict five-key root.")
	if (
		settlement_identity["authority_profile_id"] != authority_profile_id
		or not _is_safe_integer(
			settlement_identity["allocation_index"],
			0,
			MAX_ALLOCATION_INDEX
		)
		or typeof(settlement_identity["settlement_id"]) != TYPE_STRING
		or not _is_lower_hex(settlement_identity["settlement_id"].trim_prefix("settlement:"), 64)
		or not _is_non_empty_string(settlement_identity["request_id"])
		or not _is_lower_hex(settlement_identity["request_digest"], 64)
	):
		return _failure("Allocated settlement identity contains an invalid field.")
	var expected_settlement_id: Dictionary = CANONICAL_JSON.sha256([
		authority_profile_id,
		settlement_identity["allocation_index"],
	])
	if (
		not expected_settlement_id.get("ok", false)
		or settlement_identity["settlement_id"]
			!= "settlement:" + expected_settlement_id["digest"]
		or settlement_identity["request_id"] != command_result["request_id"]
		or settlement_identity["request_digest"] != command_result["request_digest"]
	):
		return _failure("Allocated settlement identity does not belong to this command.")
	if not _has_exact_keys(plan, [
		"character_id",
		"created_at_utc",
		"random_state",
		"rules_hash",
		"reservation_profile_revision",
		"initial_character_digest",
	]):
		return _failure("Character creation plan must match its strict six-key root.")
	var expected_character_id: Dictionary = CANONICAL_JSON.sha256([
		"new_character",
		settlement_identity["settlement_id"],
	])
	if (
		not expected_character_id.get("ok", false)
		or typeof(plan["character_id"]) != TYPE_STRING
		or plan["character_id"] != "character:" + expected_character_id["digest"]
		or not IDENTITY_VALIDATOR.is_valid_utc_seconds(plan["created_at_utc"])
		or not RANDOM_STREAM.validate_state(plan["random_state"]).is_empty()
		or typeof(plan["random_state"]["next_block"]) != TYPE_INT
		or plan["random_state"]["next_block"] != 0
		or not _is_lower_hex(plan["rules_hash"], 64)
		or not _is_lower_hex(plan["initial_character_digest"], 64)
		or not _is_safe_integer(
			plan["reservation_profile_revision"],
			1,
			9007199254740990
		)
		or plan["reservation_profile_revision"]
			!= command["expected_profile_revision"] + 1
	):
		return _failure("Character creation plan is invalid or belongs to another reservation.")
	var identity: Dictionary = {
		"character_id": plan["character_id"],
		"name": command["name"],
		"class_id": command["class_id"],
		"appearance": command["appearance"].duplicate(true),
		"created_at_utc": plan["created_at_utc"],
	}
	var validation: Dictionary = IDENTITY_VALIDATOR.validate(identity)
	if not validation.get("ok", false):
		return _failure("Constructed character identity is invalid: %s" % validation.get("error", "unknown"))
	return {
		"ok": true,
		"identity": validation["identity"],
	}


static func build_reserved_event(
	command: Variant,
	authority_profile_id: String,
	settlement_identity: Variant,
	plan: Variant
) -> Dictionary:
	var identity_result: Dictionary = build_character_identity(
		command,
		authority_profile_id,
		settlement_identity,
		plan
	)
	if not identity_result.get("ok", false):
		return identity_result
	var command_result: Dictionary = identify(command, authority_profile_id)
	return {
		"ok": true,
		"event": {
			"phase": "reserved",
			"identity": settlement_identity.duplicate(true),
			"command": command_result["command"],
			"plan": plan.duplicate(true),
		},
	}


static func build_aborted_event(
	reserved_event: Variant,
	authority_profile_id: String
) -> Dictionary:
	if not _has_exact_keys(reserved_event, ["phase", "identity", "command", "plan"]):
		return _failure("Only a strict reserved character creation event can be aborted.")
	if reserved_event["phase"] != "reserved":
		return _failure("Only a reserved character creation event can be aborted.")
	var identity_result: Dictionary = build_character_identity(
		reserved_event["command"],
		authority_profile_id,
		reserved_event["identity"],
		reserved_event["plan"]
	)
	if not identity_result.get("ok", false):
		return identity_result
	var reservation_revision: Variant = reserved_event["plan"]["reservation_profile_revision"]
	if (
		typeof(reservation_revision) != TYPE_INT
		or reservation_revision < 1
		or reservation_revision >= 9007199254740991
	):
		return _failure("Reserved profile revision cannot advance to a decision revision.")
	return {
		"ok": true,
		"event": {
			"phase": "aborted",
			"identity": reserved_event["identity"].duplicate(true),
			"command": reserved_event["command"].duplicate(true),
			"plan": reserved_event["plan"].duplicate(true),
			"decision_profile_revision": reservation_revision + 1,
			"reason": "user_cancelled",
		},
	}


static func identify(command: Variant, authority_profile_id: String) -> Dictionary:
	if not _has_exact_keys(command, [
		"command_id",
		"expected_profile_revision",
		"name",
		"class_id",
		"appearance",
	]):
		return _failure("Character creation command must match its strict five-key root.")
	if not _is_valid_profile_id(authority_profile_id):
		return _failure("Authority profile ID is invalid.")
	if (
		typeof(command["command_id"]) != TYPE_STRING
		or not _is_lower_hex(command["command_id"], 32)
	):
		return _failure("Command ID must be sixteen CSPRNG bytes encoded as lowercase hex.")
	if (
		typeof(command["expected_profile_revision"]) != TYPE_INT
		or command["expected_profile_revision"] < 0
		or command["expected_profile_revision"] > MAX_PROFILE_REVISION - 2
	):
		return _failure("Expected profile revision cannot safely reserve and decide a creation.")
	if typeof(command["name"]) != TYPE_STRING:
		return _failure("Character name must be a string.")
	var name_result: Dictionary = IDENTITY_VALIDATOR.UNICODE_NORMALIZER.normalize_character_name(
		command["name"]
	)
	if (
		not name_result.get("ok", false)
		or name_result["character_name"] != command["name"]
	):
		return _failure("Character name must be trimmed, NFC, and valid.")
	var identity: Dictionary = {
		"character_id": "character:identity-validation",
		"name": command["name"],
		"class_id": command["class_id"],
		"appearance": command["appearance"],
		"created_at_utc": "2000-01-01T00:00:00Z",
	}
	var identity_result: Dictionary = IDENTITY_VALIDATOR.validate(identity)
	if not identity_result.get("ok", false):
		return _failure("Character command identity is invalid: %s" % identity_result.get("error", "unknown"))

	var command_copy: Dictionary = command.duplicate(true)
	var request_id_result: Dictionary = CANONICAL_JSON.encode([
		"new_character",
		authority_profile_id,
		command["command_id"],
	])
	if not request_id_result.get("ok", false):
		return _failure(request_id_result.get("error", "Request ID encoding failed."))
	var digest_result: Dictionary = CANONICAL_JSON.sha256(command_copy)
	if not digest_result.get("ok", false):
		return _failure(digest_result.get("error", "Command digest failed."))
	return {
		"ok": true,
		"request_id": request_id_result["text"],
		"request_digest": digest_result["digest"],
		"command": command_copy,
	}


static func _has_exact_keys(value: Variant, expected_keys: Array) -> bool:
	if not value is Dictionary or value.size() != expected_keys.size():
		return false
	for key: String in expected_keys:
		if not value.has(key):
			return false
	return true


static func _is_valid_profile_id(value: String) -> bool:
	if value.length() != 40 or not value.begins_with("profile_"):
		return false
	for index: int in range(8, value.length()):
		var codepoint: int = value.unicode_at(index)
		if not (codepoint in range(48, 58) or codepoint in range(97, 103)):
			return false
	return true


static func _is_lower_hex(value: String, expected_length: int) -> bool:
	if value.length() != expected_length:
		return false
	for index: int in range(value.length()):
		var codepoint: int = value.unicode_at(index)
		if not (codepoint in range(48, 58) or codepoint in range(97, 103)):
			return false
	return true


static func _is_non_empty_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.strip_edges().is_empty()


static func _is_safe_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (
		typeof(value) == TYPE_INT
		and value >= minimum
		and value <= maximum
	)


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
	}
