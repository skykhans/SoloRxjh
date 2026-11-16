extends RefCounted

const ALGORITHM: String = "sha256_counter_53_v1"
const HASH_PREFIX: String = "SoloRxjh/RNG/v1\n"
const MAX_SAFE_INTEGER: int = 9007199254740991
const SAMPLE_SPACE: int = 9007199254740992

var seed_hex: String = ""
var next_block: int = 0
var validation_error: String = "Random state is required."


func _init(state: Variant = null) -> void:
	validation_error = validate_state(state)
	if not validation_error.is_empty():
		return

	seed_hex = state["seed_hex"]
	next_block = int(state["next_block"])


static func validate_state(state: Variant) -> String:
	if not state is Dictionary:
		return "Random state must be an object."
	if state.size() != 3:
		return "Random state must contain exactly three fields."
	if state.get("algorithm") != ALGORITHM:
		return "Random state algorithm is unsupported."
	if typeof(state.get("seed_hex")) != TYPE_STRING:
		return "Random state seed_hex must be a string."
	if not _is_seed_hex(state["seed_hex"]):
		return "Random state seed_hex must contain 64 lowercase hexadecimal characters."
	if not _is_safe_integer(state.get("next_block"), 0, MAX_SAFE_INTEGER):
		return "Random state next_block is outside the safe integer range."
	return ""


static func block_sample(seed: Variant, block_index: Variant) -> Dictionary:
	if typeof(seed) != TYPE_STRING or not _is_seed_hex(seed):
		return _failure("seed_hex must contain 64 lowercase hexadecimal characters.")
	if not _is_safe_integer(block_index, 0, MAX_SAFE_INTEGER - 1):
		return _failure("block_index must be an integer.")
	var index: int = int(block_index)

	var payload: String = "%s%s\n%d\n" % [HASH_PREFIX, seed, index]
	var hasher: HashingContext = HashingContext.new()
	var start_error: Error = hasher.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		return _failure("SHA-256 initialization failed: %s" % error_string(start_error))
	var update_error: Error = hasher.update(payload.to_utf8_buffer())
	if update_error != OK:
		return _failure("SHA-256 input failed: %s" % error_string(update_error))

	var digest: PackedByteArray = hasher.finish()
	if digest.size() != 32:
		return _failure("SHA-256 returned an invalid digest length.")

	var sample53: int = 0
	for byte_index: int in range(6):
		sample53 = sample53 * 256 + digest[byte_index]
	sample53 = sample53 * 32 + (digest[6] >> 3)

	return {
		"ok": true,
		"sha256_hex": digest.hex_encode(),
		"sample53": sample53,
	}


func draw_integer(purpose: Variant, low: Variant, high: Variant) -> Dictionary:
	if not validation_error.is_empty():
		return _failure(validation_error)
	if typeof(purpose) != TYPE_STRING or purpose.is_empty():
		return _failure("Draw purpose must be a non-empty string.")
	if not _is_safe_integer(low, -MAX_SAFE_INTEGER, MAX_SAFE_INTEGER):
		return _failure("Draw lower bound must be a safe integer.")
	if not _is_safe_integer(high, -MAX_SAFE_INTEGER, MAX_SAFE_INTEGER):
		return _failure("Draw upper bound must be a safe integer.")
	var lower: int = int(low)
	var upper: int = int(high)
	if lower > upper:
		return _failure("Draw lower bound must not exceed the upper bound.")

	var width: int = upper - lower + 1
	if width < 1 or width > SAMPLE_SPACE:
		return _failure("Draw interval width must be within 1..2^53.")

	if width == 1:
		return {
			"ok": true,
			"result": lower,
			"draw": null,
			"state_after": to_state(),
		}

	var limit: int = SAMPLE_SPACE - (SAMPLE_SPACE % width)
	var block_index: int = next_block
	while block_index < MAX_SAFE_INTEGER:
		var block: Dictionary = block_sample(seed_hex, block_index)
		if not block["ok"]:
			return _failure(block["error"])
		block_index += 1

		var sample53: int = block["sample53"]
		if sample53 >= limit:
			continue

		var result: int = lower + (sample53 % width)
		return {
			"ok": true,
			"result": result,
			"draw": {
				"purpose": purpose,
				"low": lower,
				"high": upper,
				"result": result,
				"next_block_before": next_block,
				"next_block_after": block_index,
			},
			"state_after": _state_at(block_index),
		}

	return _failure("Random block counter is exhausted.")


func draw_probability(purpose: Variant, probability_basis_points: Variant) -> Dictionary:
	if not validation_error.is_empty():
		return _failure(validation_error)
	if not _is_safe_integer(probability_basis_points, 0, 10000):
		return _failure("Probability must be an integer.")
	var probability: int = int(probability_basis_points)
	if probability == 0:
		return {
			"ok": true,
			"result": false,
			"draw": null,
			"state_after": to_state(),
		}
	if probability == 10000:
		return {
			"ok": true,
			"result": true,
			"draw": null,
			"state_after": to_state(),
		}

	var result: Dictionary = draw_integer(purpose, 0, 9999)
	if not result["ok"]:
		return result
	result["result"] = result["result"] < probability
	return result


func to_state() -> Dictionary:
	if not validation_error.is_empty():
		return {}
	return _state_at(next_block)


func _state_at(block_index: int) -> Dictionary:
	return {
		"algorithm": ALGORITHM,
		"seed_hex": seed_hex,
		"next_block": block_index,
	}


static func _is_seed_hex(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		var codepoint: int = value.unicode_at(index)
		if not (
			(codepoint >= 48 and codepoint <= 57)
			or (codepoint >= 97 and codepoint <= 102)
		):
			return false
	return true


static func _is_safe_integer(value: Variant, minimum: int, maximum: int) -> bool:
	var value_type: int = typeof(value)
	if value_type == TYPE_INT:
		return value >= minimum and value <= maximum
	if value_type != TYPE_FLOAT:
		return false

	var numeric_value: float = value
	if not is_finite(numeric_value) or floorf(numeric_value) != numeric_value:
		return false
	return numeric_value >= float(minimum) and numeric_value < float(maximum + 1)


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
	}
