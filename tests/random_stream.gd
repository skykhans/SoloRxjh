extends SceneTree

const RANDOM_STREAM: Script = preload("res://scripts/gameplay/random_stream.gd")
const RANDOM_CONTRACT_PATH: String = "res://docs/contracts/随机序列.v1.json"


func _initialize() -> void:
	var contract_file: FileAccess = FileAccess.open(RANDOM_CONTRACT_PATH, FileAccess.READ)
	if not _require(contract_file != null, "Random sequence contract could not be opened."):
		return

	var contract_json: JSON = JSON.new()
	if not _require(
		contract_json.parse(contract_file.get_as_text()) == OK,
		"Random sequence contract is invalid JSON."
	):
		return

	var vectors: Array = contract_json.data["block_vectors"]
	for vector: Dictionary in vectors:
		var block: Dictionary = RANDOM_STREAM.block_sample(
			vector["seed_hex"],
			vector["block_index"]
		)
		if not _require(
			block.get("ok", false),
			"Contract block vector failed to calculate: %s" % block
		):
			return
		if not _require(
			block["sha256_hex"] == vector["sha256_hex"]
				and block["sample53"] == vector["sample53"],
			"Random block vector mismatch at index %s." % vector["block_index"]
		):
			return

	if not _test_rejection_sampling():
		return
	if not _test_deterministic_ranges():
		return
	if not _test_probability_boundaries():
		return
	if not _test_invalid_states_and_exhaustion():
		return

	print("Random stream contract vectors and boundaries passed.")
	quit(0)


func _test_rejection_sampling() -> bool:
	var stream: Variant = RANDOM_STREAM.new(_zero_seed_state())
	if not _require(stream.validation_error.is_empty(), "Valid random state was rejected."):
		return false

	var result: Dictionary = stream.draw_integer("rejection_probe", 0, 4503599627370496)
	if not _require(result.get("ok", false), "Rejection sampling failed."):
		return false
	if not _require(
		result["result"] == 413263060333754
			and result["draw"]["next_block_before"] == 0
			and result["draw"]["next_block_after"] == 2
			and result["state_after"]["next_block"] == 2,
		"Rejected block was not included in the draw interval."
	):
		return false
	return _require(
		stream.to_state()["next_block"] == 0,
		"Drawing mutated the original random state."
	)


func _test_deterministic_ranges() -> bool:
	var stream: Variant = RANDOM_STREAM.new(_zero_seed_state())
	var single_value: Dictionary = stream.draw_integer("single_value", 17, 17)
	if not _require(
		single_value.get("ok", false)
			and single_value["result"] == 17
			and single_value["draw"] == null
			and single_value["state_after"]["next_block"] == 0,
		"Single-value draw consumed randomness."
	):
		return false

	var full_width: Dictionary = stream.draw_integer("full_width", 0, 9007199254740991)
	return _require(
		full_width.get("ok", false)
			and full_width["result"] == 5690699719407391
			and full_width["draw"]["next_block_after"] == 1,
		"2^53-wide draw did not use the complete sample."
	)


func _test_probability_boundaries() -> bool:
	var stream: Variant = RANDOM_STREAM.new(_zero_seed_state())
	var impossible: Dictionary = stream.draw_probability("zero_probability", 0)
	var certain: Dictionary = stream.draw_probability("certain_probability", 10000)
	if not _require(
		impossible.get("ok", false)
			and impossible["result"] == false
			and impossible["draw"] == null
			and certain.get("ok", false)
			and certain["result"] == true
			and certain["draw"] == null,
		"Deterministic probability boundary returned the wrong result."
	):
		return false
	if not _require(stream.to_state()["next_block"] == 0, "Probability boundary consumed randomness."):
		return false

	var ordinary: Dictionary = stream.draw_probability("ordinary_probability", 5000)
	return _require(
		ordinary.get("ok", false)
			and ordinary["result"] == false
			and ordinary["draw"]["result"] == 7391
			and ordinary["state_after"]["next_block"] == 1,
		"Ordinary probability did not draw from 0..9999."
	)


func _test_invalid_states_and_exhaustion() -> bool:
	var invalid_seed: Variant = RANDOM_STREAM.new(
		{
			"algorithm": "sha256_counter_53_v1",
			"seed_hex": "A".repeat(64),
			"next_block": 0,
		}
	)
	if not _require(
		not invalid_seed.validation_error.is_empty(),
		"Uppercase seed was accepted."
	):
		return false

	var extra_field: Variant = RANDOM_STREAM.new(
		{
			"algorithm": "sha256_counter_53_v1",
			"seed_hex": "0".repeat(64),
			"next_block": 0,
			"current_state": 0,
		}
	)
	if not _require(not extra_field.validation_error.is_empty(), "Unknown random field was accepted."):
		return false

	var fractional_counter: Variant = RANDOM_STREAM.new(
		{
			"algorithm": "sha256_counter_53_v1",
			"seed_hex": "0".repeat(64),
			"next_block": 1.5,
		}
	)
	if not _require(
		not fractional_counter.validation_error.is_empty(),
		"Fractional random counter was accepted."
	):
		return false

	var json_integer_counter: Variant = RANDOM_STREAM.new(
		{
			"algorithm": "sha256_counter_53_v1",
			"seed_hex": "0".repeat(64),
			"next_block": 0.0,
		}
	)
	if not _require(
		json_integer_counter.validation_error.is_empty(),
		"JSON integer representation was rejected."
	):
		return false

	var exhausted: Variant = RANDOM_STREAM.new(
		{
			"algorithm": "sha256_counter_53_v1",
			"seed_hex": "0".repeat(64),
			"next_block": 9007199254740991,
		}
	)
	var exhausted_draw: Dictionary = exhausted.draw_integer("exhausted", 0, 1)
	return _require(
		not exhausted_draw.get("ok", false)
			and exhausted.to_state()["next_block"] == 9007199254740991,
		"Exhausted counter changed or produced a random result."
	)


func _zero_seed_state() -> Dictionary:
	return {
		"algorithm": "sha256_counter_53_v1",
		"seed_hex": "0".repeat(64),
		"next_block": 0,
	}


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false
