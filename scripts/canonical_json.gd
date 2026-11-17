extends RefCounted


static func encode(value: Variant) -> Dictionary:
	var encoded: Dictionary = _encode_value(value)
	if not encoded.get("ok", false):
		return encoded
	return {
		"ok": true,
		"text": encoded["text"],
		"bytes": encoded["text"].to_utf8_buffer(),
	}


static func sha256(value: Variant) -> Dictionary:
	var encoded: Dictionary = encode(value)
	if not encoded.get("ok", false):
		return encoded
	var bytes: PackedByteArray = encoded["bytes"]
	var hashing_context: HashingContext = HashingContext.new()
	if hashing_context.start(HashingContext.HASH_SHA256) != OK:
		return _failure("SHA-256 initialization failed.")
	if hashing_context.update(bytes) != OK:
		return _failure("SHA-256 update failed.")
	var digest_bytes: PackedByteArray = hashing_context.finish()
	return {
		"ok": true,
		"text": encoded["text"],
		"digest": digest_bytes.hex_encode(),
	}


static func _encode_value(value: Variant) -> Dictionary:
	match typeof(value):
		TYPE_NIL:
			return _success("null")
		TYPE_BOOL:
			return _success("true" if value else "false")
		TYPE_INT:
			return _success(str(value))
		TYPE_FLOAT:
			return _failure("Floating point values are forbidden.")
		TYPE_STRING:
			return _encode_string(value)
		TYPE_ARRAY:
			var elements: PackedStringArray = PackedStringArray()
			for item: Variant in value:
				var encoded_item: Dictionary = _encode_value(item)
				if not encoded_item.get("ok", false):
					return encoded_item
				elements.append(encoded_item["text"])
			return _success("[%s]" % ",".join(elements))
		TYPE_DICTIONARY:
			return _encode_dictionary(value)
		_:
			return _failure("Unsupported value type: %s." % type_string(typeof(value)))


static func _encode_dictionary(value: Dictionary) -> Dictionary:
	var keys: Array[String] = []
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING:
			return _failure("Object keys must be strings.")
		keys.append(key)
	keys.sort_custom(_unicode_codepoint_less)

	var members: PackedStringArray = PackedStringArray()
	for key: String in keys:
		var encoded_key: Dictionary = _encode_string(key)
		if not encoded_key.get("ok", false):
			return encoded_key
		var encoded_value: Dictionary = _encode_value(value[key])
		if not encoded_value.get("ok", false):
			return encoded_value
		members.append("%s:%s" % [encoded_key["text"], encoded_value["text"]])
	return _success("{%s}" % ",".join(members))


static func _encode_string(value: String) -> Dictionary:
	var output: String = "\""
	for index: int in range(value.length()):
		var codepoint: int = value.unicode_at(index)
		if codepoint >= 0xD800 and codepoint <= 0xDFFF:
			return _failure("Strings cannot contain isolated surrogate code points.")
		match codepoint:
			0x22:
				output += "\\\""
			0x5C:
				output += "\\\\"
			_:
				if codepoint <= 0x1F:
					output += "\\u%04x" % codepoint
				else:
					output += String.chr(codepoint)
	output += "\""
	return _success(output)


static func _unicode_codepoint_less(left: String, right: String) -> bool:
	var left_index: int = 0
	var right_index: int = 0
	while left_index < left.length() and right_index < right.length():
		var left_codepoint: int = left.unicode_at(left_index)
		var right_codepoint: int = right.unicode_at(right_index)
		if left_codepoint != right_codepoint:
			return left_codepoint < right_codepoint
		left_index += 1
		right_index += 1
	return left.length() < right.length()


static func _success(text: String) -> Dictionary:
	return {
		"ok": true,
		"text": text,
	}


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
	}
