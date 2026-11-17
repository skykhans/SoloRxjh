class_name Unicode15Normalizer
extends RefCounted

const DATA: Script = preload("res://scripts/unicode15_data.gd")


static func normalize_profile_name(raw_name: String) -> Dictionary:
	if _has_forbidden_codepoint(raw_name):
		return _failure("profile_name_contains_control")

	var trimmed: String = _trim_unicode_whitespace(raw_name)
	if trimmed.is_empty():
		return _failure("profile_name_length")

	var display_name: String = _normalize_nfc(trimmed)
	if (
		display_name.length() < 2
		or display_name.length() > 16
		or _has_forbidden_codepoint(display_name)
	):
		return _failure("profile_name_invalid")

	var folded: String = _casefold(display_name)
	var comparison_key: String = _normalize_nfc(folded)
	return {
		"ok": true,
		"profile_name": display_name,
		"comparison_key": comparison_key,
	}


static func normalize_character_name(raw_name: String) -> Dictionary:
	if _has_forbidden_codepoint(raw_name):
		return _failure("character_name_contains_control")

	var trimmed: String = _trim_unicode_whitespace(raw_name)
	if trimmed.is_empty():
		return _failure("character_name_length")

	var display_name: String = _normalize_nfc(trimmed)
	if (
		display_name.length() < 2
		or display_name.length() > 12
		or _has_forbidden_codepoint(display_name)
	):
		return _failure("character_name_invalid")

	var folded: String = _casefold(display_name)
	return {
		"ok": true,
		"character_name": display_name,
		"comparison_key": _normalize_nfc(folded),
	}


static func _trim_unicode_whitespace(value: String) -> String:
	var first: int = 0
	var last: int = value.length()
	while first < last and DATA.WHITE_SPACE.has(value.unicode_at(first)):
		first += 1
	while last > first and DATA.WHITE_SPACE.has(value.unicode_at(last - 1)):
		last -= 1
	return value.substr(first, last - first)


static func _has_forbidden_codepoint(value: String) -> bool:
	for index: int in range(value.length()):
		var codepoint: int = value.unicode_at(index)
		if (
			codepoint < 0x20
			or codepoint in range(0x7F, 0xA0)
			or codepoint in range(0xD800, 0xE000)
		):
			return true
	return false


static func _normalize_nfc(value: String) -> String:
	var decomposed: Array[int] = []
	for index: int in range(value.length()):
		_append_canonical_decomposition(value.unicode_at(index), decomposed)
	_canonical_order(decomposed)
	return _from_codepoints(_canonical_compose(decomposed))


static func _append_canonical_decomposition(codepoint: int, output: Array[int]) -> void:
	const S_BASE: int = 0xAC00
	const L_BASE: int = 0x1100
	const V_BASE: int = 0x1161
	const T_BASE: int = 0x11A7
	const V_COUNT: int = 21
	const T_COUNT: int = 28
	const N_COUNT: int = V_COUNT * T_COUNT
	const S_COUNT: int = 19 * N_COUNT

	var syllable_index: int = codepoint - S_BASE
	if syllable_index >= 0 and syllable_index < S_COUNT:
		output.push_back(L_BASE + syllable_index / N_COUNT)
		output.push_back(V_BASE + (syllable_index % N_COUNT) / T_COUNT)
		var trailing_index: int = syllable_index % T_COUNT
		if trailing_index != 0:
			output.push_back(T_BASE + trailing_index)
		return

	if DATA.CANONICAL_DECOMPOSITION.has(codepoint):
		for part: int in DATA.CANONICAL_DECOMPOSITION[codepoint]:
			_append_canonical_decomposition(part, output)
		return
	output.push_back(codepoint)


static func _canonical_order(codepoints: Array[int]) -> void:
	for index: int in range(1, codepoints.size()):
		var current: int = codepoints[index]
		var current_class: int = _combining_class(current)
		if current_class == 0:
			continue
		var destination: int = index
		while destination > 0:
			var previous_class: int = _combining_class(codepoints[destination - 1])
			if previous_class == 0 or previous_class <= current_class:
				break
			codepoints[destination] = codepoints[destination - 1]
			destination -= 1
		codepoints[destination] = current


static func _canonical_compose(codepoints: Array[int]) -> Array[int]:
	var composed: Array[int] = []
	var starter_index: int = -1
	var starter: int = 0
	var last_class: int = 0
	for codepoint: int in codepoints:
		var current_class: int = _combining_class(codepoint)
		var composite: int = -1
		if starter_index >= 0 and (last_class == 0 or last_class < current_class):
			composite = _compose_pair(starter, codepoint)
		if composite >= 0:
			composed[starter_index] = composite
			starter = composite
			continue
		if current_class == 0:
			starter_index = composed.size()
			starter = codepoint
		composed.push_back(codepoint)
		last_class = current_class
	return composed


static func _compose_pair(first: int, second: int) -> int:
	const S_BASE: int = 0xAC00
	const L_BASE: int = 0x1100
	const V_BASE: int = 0x1161
	const T_BASE: int = 0x11A7
	const L_COUNT: int = 19
	const V_COUNT: int = 21
	const T_COUNT: int = 28
	const N_COUNT: int = V_COUNT * T_COUNT
	const S_COUNT: int = L_COUNT * N_COUNT

	var leading_index: int = first - L_BASE
	var vowel_index: int = second - V_BASE
	if leading_index >= 0 and leading_index < L_COUNT and vowel_index >= 0 and vowel_index < V_COUNT:
		return S_BASE + (leading_index * V_COUNT + vowel_index) * T_COUNT

	var syllable_index: int = first - S_BASE
	var trailing_index: int = second - T_BASE
	if (
		syllable_index >= 0
		and syllable_index < S_COUNT
		and syllable_index % T_COUNT == 0
		and trailing_index > 0
		and trailing_index < T_COUNT
	):
		return first + trailing_index

	var key: int = (first << 21) | second
	return DATA.COMPOSITION.get(key, -1)


static func _combining_class(codepoint: int) -> int:
	return DATA.COMBINING_CLASS.get(codepoint, 0)


static func _casefold(value: String) -> String:
	var codepoints: Array[int] = []
	for index: int in range(value.length()):
		var codepoint: int = value.unicode_at(index)
		if DATA.CASE_FOLD.has(codepoint):
			for folded_codepoint: int in DATA.CASE_FOLD[codepoint]:
				codepoints.push_back(folded_codepoint)
		else:
			codepoints.push_back(codepoint)
	return _from_codepoints(codepoints)


static func _from_codepoints(codepoints: Array[int]) -> String:
	var result: String = ""
	for codepoint: int in codepoints:
		result += String.chr(codepoint)
	return result


static func _failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"error": error,
	}
