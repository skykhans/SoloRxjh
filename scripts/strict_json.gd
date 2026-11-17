extends RefCounted


static func has_duplicate_object_keys(source: String) -> bool:
	var cursor: Dictionary = {"index": 0}
	return _scan_value(source, cursor)


static func has_integer_object_field_token(source: String, field_name: String) -> bool:
	var cursor: Dictionary = {"index": 0}
	_skip_whitespace(source, cursor)
	if not _consume_if(source, cursor, 0x7B):
		return false
	_skip_whitespace(source, cursor)
	if _consume_if(source, cursor, 0x7D):
		return false
	while cursor["index"] < source.length():
		_skip_whitespace(source, cursor)
		if cursor["index"] >= source.length() or source.unicode_at(cursor["index"]) != 0x22:
			return false
		var key_result: Dictionary = _read_string(source, cursor)
		if key_result.is_empty():
			return false
		_skip_whitespace(source, cursor)
		if not _consume_if(source, cursor, 0x3A):
			return false
		_skip_whitespace(source, cursor)
		if key_result["value"] == field_name:
			var token_start: int = cursor["index"]
			while cursor["index"] < source.length():
				var codepoint: int = source.unicode_at(cursor["index"])
				if (
					codepoint in [0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x7D]
				):
					break
				cursor["index"] += 1
			return _is_integer_token(source.substr(token_start, cursor["index"] - token_start))
		if _scan_value(source, cursor):
			return false
		_skip_whitespace(source, cursor)
		if _consume_if(source, cursor, 0x7D):
			return false
		if not _consume_if(source, cursor, 0x2C):
			return false
	return false


static func has_integer_array_item_token(
		source: String,
		object_field_name: String,
		item_index: int
) -> bool:
	return _has_integer_array_item_token(source, object_field_name, "", item_index)


static func has_nested_integer_array_item_token(
		source: String,
		parent_field_name: String,
		object_field_name: String,
		item_index: int
) -> bool:
	return _has_integer_array_item_token(
		source,
		object_field_name,
		parent_field_name,
		item_index
	)


static func _has_integer_array_item_token(
		source: String,
		object_field_name: String,
		parent_field_name: String,
		item_index: int
) -> bool:
	if item_index < 0:
		return false
	var cursor: Dictionary = {"index": 0}
	_skip_whitespace(source, cursor)
	if not _consume_if(source, cursor, 0x7B):
		return false
	_skip_whitespace(source, cursor)
	if _consume_if(source, cursor, 0x7D):
		return false
	while cursor["index"] < source.length():
		_skip_whitespace(source, cursor)
		if cursor["index"] >= source.length() or source.unicode_at(cursor["index"]) != 0x22:
			return false
		var key_result: Dictionary = _read_string(source, cursor)
		if key_result.is_empty():
			return false
		_skip_whitespace(source, cursor)
		if not _consume_if(source, cursor, 0x3A):
			return false
		_skip_whitespace(source, cursor)
		var target_cursor: Dictionary = {}
		if not parent_field_name.is_empty():
			if key_result["value"] != parent_field_name:
				if _scan_value(source, cursor):
					return false
				_skip_whitespace(source, cursor)
				if _consume_if(source, cursor, 0x7D):
					return false
				if not _consume_if(source, cursor, 0x2C):
					return false
				continue
			if not _consume_if(source, cursor, 0x7B):
				return false
			var nested_cursor: Dictionary = {"index": cursor["index"]}
			_skip_whitespace(source, nested_cursor)
			if _consume_if(source, nested_cursor, 0x7D):
				return false
			while nested_cursor["index"] < source.length():
				_skip_whitespace(source, nested_cursor)
				if (
					nested_cursor["index"] >= source.length()
					or source.unicode_at(nested_cursor["index"]) != 0x22
				):
					return false
				var nested_key: Dictionary = _read_string(source, nested_cursor)
				if nested_key.is_empty():
					return false
				_skip_whitespace(source, nested_cursor)
				if not _consume_if(source, nested_cursor, 0x3A):
					return false
				_skip_whitespace(source, nested_cursor)
				if nested_key["value"] == object_field_name:
					target_cursor = nested_cursor
					break
				if _scan_value(source, nested_cursor):
					return false
				_skip_whitespace(source, nested_cursor)
				if _consume_if(source, nested_cursor, 0x7D):
					return false
				if not _consume_if(source, nested_cursor, 0x2C):
					return false
			if target_cursor.is_empty():
				return false
			cursor = target_cursor
		elif key_result["value"] != object_field_name:
			if _scan_value(source, cursor):
				return false
			_skip_whitespace(source, cursor)
			if _consume_if(source, cursor, 0x7D):
				return false
			if not _consume_if(source, cursor, 0x2C):
				return false
			continue
		if not _consume_if(source, cursor, 0x5B):
			return false
		for index: int in range(item_index + 1):
			_skip_whitespace(source, cursor)
			if cursor["index"] >= source.length():
				return false
			var token_start: int = cursor["index"]
			while cursor["index"] < source.length():
				var codepoint: int = source.unicode_at(cursor["index"])
				if codepoint in [0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x5D]:
					break
				cursor["index"] += 1
			if index == item_index:
				return _is_integer_token(
					source.substr(token_start, cursor["index"] - token_start)
				)
			if index < item_index:
				_skip_whitespace(source, cursor)
				if (
					cursor["index"] >= source.length()
					or source.unicode_at(cursor["index"]) != 0x2C
				):
					return false
				cursor["index"] += 1
		return false
	return false


static func _scan_value(source: String, cursor: Dictionary) -> bool:
	_skip_whitespace(source, cursor)
	if cursor["index"] >= source.length():
		return false
	var codepoint: int = source.unicode_at(cursor["index"])
	if codepoint == 0x7B:
		return _scan_object(source, cursor)
	if codepoint == 0x5B:
		return _scan_array(source, cursor)
	if codepoint == 0x22:
		return not _skip_string(source, cursor)
	return _scan_primitive(source, cursor)


static func _scan_object(source: String, cursor: Dictionary) -> bool:
	cursor["index"] += 1
	_skip_whitespace(source, cursor)
	if _consume_if(source, cursor, 0x7D):
		return false
	var seen_keys: Dictionary = {}
	while cursor["index"] < source.length():
		_skip_whitespace(source, cursor)
		if cursor["index"] >= source.length() or source.unicode_at(cursor["index"]) != 0x22:
			return false
		var key_result: Dictionary = _read_string(source, cursor)
		if key_result.is_empty():
			return true
		var key: String = key_result["value"]
		if seen_keys.has(key):
			return true
		seen_keys[key] = true
		_skip_whitespace(source, cursor)
		if not _consume_if(source, cursor, 0x3A):
			return false
		if _scan_value(source, cursor):
			return true
		_skip_whitespace(source, cursor)
		if _consume_if(source, cursor, 0x7D):
			return false
		if not _consume_if(source, cursor, 0x2C):
			return false
	return false


static func _scan_array(source: String, cursor: Dictionary) -> bool:
	cursor["index"] += 1
	_skip_whitespace(source, cursor)
	if _consume_if(source, cursor, 0x5D):
		return false
	while cursor["index"] < source.length():
		if _scan_value(source, cursor):
			return true
		_skip_whitespace(source, cursor)
		if _consume_if(source, cursor, 0x5D):
			return false
		if not _consume_if(source, cursor, 0x2C):
			return false
	return false


static func _scan_primitive(source: String, cursor: Dictionary) -> bool:
	while cursor["index"] < source.length():
		var codepoint: int = source.unicode_at(cursor["index"])
		if (
			codepoint == 0x20
			or codepoint == 0x09
			or codepoint == 0x0A
			or codepoint == 0x0D
			or codepoint in [0x2C, 0x5D, 0x7D]
		):
			break
		cursor["index"] += 1
	return false


static func _read_string(source: String, cursor: Dictionary) -> Dictionary:
	cursor["index"] += 1
	var segments: PackedStringArray = []
	while cursor["index"] < source.length():
		var codepoint: int = source.unicode_at(cursor["index"])
		cursor["index"] += 1
		if codepoint == 0x22:
			return {
				"ok": true,
				"value": "".join(segments),
			}
		if codepoint < 0x20:
			return {}
		if codepoint != 0x5C:
			segments.push_back(String.chr(codepoint))
			continue
		if cursor["index"] >= source.length():
			return {}
		var escape: int = source.unicode_at(cursor["index"])
		cursor["index"] += 1
		match escape:
			0x22:
				segments.push_back("\"")
			0x5C:
				segments.push_back("\\")
			0x2F:
				segments.push_back("/")
			0x62:
				segments.push_back("\b")
			0x66:
				segments.push_back("\f")
			0x6E:
				segments.push_back("\n")
			0x72:
				segments.push_back("\r")
			0x74:
				segments.push_back("\t")
			0x75:
				var decoded: Dictionary = _read_unicode_escape(source, cursor)
				if decoded.is_empty():
					return {}
				segments.push_back(String.chr(decoded["codepoint"]))
			_:
				return {}
	return {}


static func _skip_string(source: String, cursor: Dictionary) -> bool:
	cursor["index"] += 1
	while cursor["index"] < source.length():
		var codepoint: int = source.unicode_at(cursor["index"])
		cursor["index"] += 1
		if codepoint == 0x22:
			return true
		if codepoint == 0x5C:
			if cursor["index"] >= source.length():
				return false
			cursor["index"] += 1
	return false


static func _read_unicode_escape(source: String, cursor: Dictionary) -> Dictionary:
	if cursor["index"] + 4 > source.length():
		return {}
	var codepoint: int = 0
	for offset: int in range(4):
		var digit: int = _hex_value(source.unicode_at(cursor["index"] + offset))
		if digit < 0:
			return {}
		codepoint = codepoint * 16 + digit
	cursor["index"] += 4
	if codepoint >= 0xD800 and codepoint <= 0xDBFF:
		if (
			cursor["index"] + 6 > source.length()
			or source.unicode_at(cursor["index"]) != 0x5C
			or source.unicode_at(cursor["index"] + 1) != 0x75
		):
			return {}
		cursor["index"] += 2
		var low: int = 0
		for offset: int in range(4):
			var digit: int = _hex_value(source.unicode_at(cursor["index"] + offset))
			if digit < 0:
				return {}
			low = low * 16 + digit
		if low < 0xDC00 or low > 0xDFFF:
			return {}
		cursor["index"] += 4
		codepoint = 0x10000 + ((codepoint - 0xD800) << 10) + low - 0xDC00
	elif codepoint >= 0xDC00 and codepoint <= 0xDFFF:
		return {}
	return {
		"codepoint": codepoint,
	}


static func _hex_value(codepoint: int) -> int:
	if codepoint in range(48, 58):
		return codepoint - 48
	if codepoint in range(65, 71):
		return codepoint - 55
	if codepoint in range(97, 103):
		return codepoint - 87
	return -1


static func _is_integer_token(token: String) -> bool:
	if token.is_empty():
		return false
	var index: int = 0
	if token.unicode_at(index) == 0x2D:
		index += 1
		if index >= token.length():
			return false
	if token.unicode_at(index) == 0x30:
		return index == token.length() - 1
	if token.unicode_at(index) not in range(49, 58):
		return false
	index += 1
	while index < token.length():
		if token.unicode_at(index) not in range(48, 58):
			return false
		index += 1
	return true


static func _skip_whitespace(source: String, cursor: Dictionary) -> void:
	while cursor["index"] < source.length():
		var codepoint: int = source.unicode_at(cursor["index"])
		if codepoint not in [0x20, 0x09, 0x0A, 0x0D]:
			return
		cursor["index"] += 1


static func _consume_if(source: String, cursor: Dictionary, expected: int) -> bool:
	if (
		cursor["index"] >= source.length()
		or source.unicode_at(cursor["index"]) != expected
	):
		return false
	cursor["index"] += 1
	return true
