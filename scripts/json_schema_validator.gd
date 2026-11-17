class_name JsonSchemaValidator
extends RefCounted

const CONTRACT_DIRECTORY: String = "res://docs/contracts"
const ASSERTION_KEYWORDS: PackedStringArray = [
	"type",
	"$ref",
	"const",
	"enum",
	"allOf",
	"anyOf",
	"oneOf",
	"not",
	"if",
	"then",
	"else",
	"required",
	"properties",
	"propertyNames",
	"patternProperties",
	"additionalProperties",
	"minProperties",
	"maxProperties",
	"dependentRequired",
	"dependentSchemas",
	"items",
	"prefixItems",
	"contains",
	"minContains",
	"maxContains",
	"minItems",
	"maxItems",
	"uniqueItems",
	"minLength",
	"maxLength",
	"pattern",
	"minimum",
	"maximum",
	"exclusiveMinimum",
	"exclusiveMaximum",
	"multipleOf",
]
const ANNOTATION_KEYWORDS: PackedStringArray = [
	"$schema",
	"$id",
	"$defs",
	"definitions",
	"$comment",
	"title",
	"description",
	"default",
	"examples",
	"deprecated",
	"readOnly",
	"writeOnly",
	"format",
	"contentEncoding",
	"contentMediaType",
	"$anchor",
	"$dynamicAnchor",
]

var _schemas_by_id: Dictionary = {}
var _schema_index_loaded: bool = false


func validate(instance: Variant, schema: Variant) -> Dictionary:
	if not schema is Dictionary:
		return _failure("Schema root must be an object.")
	var index_error: String = _load_schema_index()
	if not index_error.is_empty():
		return _failure(index_error)
	var root_schema: Dictionary = schema
	if typeof(schema.get("$id")) == TYPE_STRING:
		root_schema = _schemas_by_id.get(schema["$id"], schema)
	var result: Dictionary = _validate_value(instance, schema, root_schema, "$", {})
	if result.get("ok", false):
		return {"ok": true}
	return _failure(result.get("error", "Schema validation failed."))


func _validate_value(
	instance: Variant,
	schema: Dictionary,
	root_schema: Dictionary,
	instance_path: String,
	ref_stack: Dictionary
) -> Dictionary:
	for key: Variant in schema.keys():
		if (
			typeof(key) != TYPE_STRING
			or not ASSERTION_KEYWORDS.has(key)
				and not ANNOTATION_KEYWORDS.has(key)
		):
			return _invalid(
				instance_path,
				"unsupported schema keyword %s" % str(key)
			)

	if schema.has("$ref"):
		if typeof(schema["$ref"]) != TYPE_STRING:
			return _invalid(instance_path, "$ref must be a string.")
		var reference: String = schema["$ref"]
		var reference_key: String = "%s@%s" % [reference, instance_path]
		if ref_stack.has(reference_key):
			return _invalid(instance_path, "cyclic schema reference.")
		var resolved: Dictionary = _resolve_reference(reference, root_schema)
		if not resolved.get("ok", false):
			return _invalid(instance_path, resolved.get("error", "unresolved $ref."))
		var next_stack: Dictionary = ref_stack.duplicate()
		next_stack[reference_key] = true
		var reference_result: Dictionary = _validate_value(
			instance,
			resolved["schema"],
			resolved["root"],
			instance_path,
			next_stack
		)
		if not reference_result.get("ok", false):
			return reference_result

	if schema.has("type") and not _matches_type(instance, schema["type"]):
		return _invalid(
			instance_path,
			"value type %s does not match %s"
			% [type_string(typeof(instance)), str(schema["type"])]
		)
	if schema.has("const") and not _json_values_equal(instance, schema["const"]):
		return _invalid(instance_path, "value does not match const.")
	if schema.has("enum"):
		var enum_match: bool = false
		for enum_value: Variant in schema["enum"]:
			if _json_values_equal(instance, enum_value):
				enum_match = true
				break
		if not enum_match:
			return _invalid(instance_path, "value is not in enum.")

	for composition_key: String in ["allOf", "anyOf", "oneOf"]:
		if not schema.has(composition_key):
			continue
		if not schema[composition_key] is Array:
			return _invalid(instance_path, "%s must be an array." % composition_key)
		var valid_count: int = 0
		for branch: Variant in schema[composition_key]:
			if not branch is Dictionary:
				return _invalid(instance_path, "%s branch must be an object." % composition_key)
			var branch_result: Dictionary = _validate_value(
				instance,
				branch,
				root_schema,
				instance_path,
				ref_stack
			)
			if branch_result.get("ok", false):
				valid_count += 1
			elif composition_key == "allOf":
				return branch_result
		if (
			composition_key == "anyOf" and valid_count == 0
			or composition_key == "oneOf" and valid_count != 1
		):
			return _invalid(instance_path, "%s branch count is invalid." % composition_key)

	if schema.has("not"):
		if not schema["not"] is Dictionary:
			return _invalid(instance_path, "not must be a schema object.")
		var not_result: Dictionary = _validate_value(
			instance,
			schema["not"],
			root_schema,
			instance_path,
			ref_stack
		)
		if not_result.get("ok", false):
			return _invalid(instance_path, "value matches forbidden schema.")
	if schema.has("if"):
		if not schema["if"] is Dictionary:
			return _invalid(instance_path, "if must be a schema object.")
		var condition: Dictionary = _validate_value(
			instance,
			schema["if"],
			root_schema,
			instance_path,
			ref_stack
		)
		var branch_key: String = "then" if condition.get("ok", false) else "else"
		if schema.has(branch_key):
			if not schema[branch_key] is Dictionary:
				return _invalid(instance_path, "%s must be a schema object." % branch_key)
			var condition_result: Dictionary = _validate_value(
				instance,
				schema[branch_key],
				root_schema,
				instance_path,
				ref_stack
			)
			if not condition_result.get("ok", false):
				return condition_result

	if instance is Dictionary:
		var object_result: Dictionary = _validate_object(
			instance,
			schema,
			root_schema,
			instance_path,
			ref_stack
		)
		if not object_result.get("ok", false):
			return object_result
	elif instance is Array:
		var array_result: Dictionary = _validate_array(
			instance,
			schema,
			root_schema,
			instance_path,
			ref_stack
		)
		if not array_result.get("ok", false):
			return array_result
	elif typeof(instance) == TYPE_STRING:
		var string_result: Dictionary = _validate_string(instance, schema, instance_path)
		if not string_result.get("ok", false):
			return string_result
	elif typeof(instance) in [TYPE_INT, TYPE_FLOAT]:
		var number_result: Dictionary = _validate_number(instance, schema, instance_path)
		if not number_result.get("ok", false):
			return number_result
	return {"ok": true}


func _validate_object(
	instance: Dictionary,
	schema: Dictionary,
	root_schema: Dictionary,
	instance_path: String,
	ref_stack: Dictionary
) -> Dictionary:
	if schema.has("minProperties") and instance.size() < int(schema["minProperties"]):
		return _invalid(instance_path, "object has too few properties.")
	if schema.has("maxProperties") and instance.size() > int(schema["maxProperties"]):
		return _invalid(instance_path, "object has too many properties.")
	if schema.has("required"):
		if not schema["required"] is Array:
			return _invalid(instance_path, "required must be an array.")
		for required_key: Variant in schema["required"]:
			if typeof(required_key) != TYPE_STRING or not instance.has(required_key):
				return _invalid(instance_path, "required property is missing.")

	var properties: Dictionary = schema.get("properties", {})
	var pattern_properties: Dictionary = schema.get("patternProperties", {})
	if not properties is Dictionary or not pattern_properties is Dictionary:
		return _invalid(instance_path, "property schemas must be objects.")
	for property_key: Variant in instance.keys():
		if typeof(property_key) != TYPE_STRING:
			return _invalid(instance_path, "object key must be a string.")
		if schema.has("propertyNames"):
			var property_name_result: Dictionary = _validate_value(
				property_key,
				schema["propertyNames"],
				root_schema,
				"%s/<key>" % instance_path,
				ref_stack
			)
			if not property_name_result.get("ok", false):
				return property_name_result
		var matched: bool = false
		if properties.has(property_key):
			var property_result: Dictionary = _validate_value(
				instance[property_key],
				properties[property_key],
				root_schema,
				"%s/%s" % [instance_path, _escape_pointer_token(property_key)],
				ref_stack
			)
			if not property_result.get("ok", false):
				return property_result
			matched = true
		for pattern: Variant in pattern_properties.keys():
			if typeof(pattern) != TYPE_STRING:
				return _invalid(instance_path, "patternProperties key must be a string.")
			var matcher: RegEx = RegEx.new()
			if matcher.compile(pattern) != OK:
				return _invalid(instance_path, "invalid patternProperties regex.")
			if matcher.search(property_key) != null:
				var pattern_result: Dictionary = _validate_value(
					instance[property_key],
					pattern_properties[pattern],
					root_schema,
					"%s/%s" % [instance_path, _escape_pointer_token(property_key)],
					ref_stack
				)
				if not pattern_result.get("ok", false):
					return pattern_result
				matched = true
		if matched or not schema.has("additionalProperties"):
			continue
		var additional: Variant = schema["additionalProperties"]
		if additional is bool:
			if not additional:
				return _invalid(instance_path, "additional property is forbidden.")
		elif additional is Dictionary:
			var additional_result: Dictionary = _validate_value(
				instance[property_key],
				additional,
				root_schema,
				"%s/%s" % [instance_path, _escape_pointer_token(property_key)],
				ref_stack
			)
			if not additional_result.get("ok", false):
				return additional_result
		else:
			return _invalid(instance_path, "additionalProperties must be a schema or boolean.")

	if schema.has("dependentRequired"):
		if not schema["dependentRequired"] is Dictionary:
			return _invalid(instance_path, "dependentRequired must be an object.")
		for source_key: Variant in schema["dependentRequired"]:
			if instance.has(source_key):
				var dependencies: Variant = schema["dependentRequired"][source_key]
				if not dependencies is Array:
					return _invalid(instance_path, "dependentRequired value must be an array.")
				for dependency: Variant in dependencies:
					if not instance.has(dependency):
						return _invalid(instance_path, "dependent property is missing.")
	if schema.has("dependentSchemas"):
		if not schema["dependentSchemas"] is Dictionary:
			return _invalid(instance_path, "dependentSchemas must be an object.")
		for source_key: Variant in schema["dependentSchemas"]:
			if instance.has(source_key):
				var dependency_result: Dictionary = _validate_value(
					instance,
					schema["dependentSchemas"][source_key],
					root_schema,
					instance_path,
					ref_stack
				)
				if not dependency_result.get("ok", false):
					return dependency_result
	return {"ok": true}


func _validate_array(
	instance: Array,
	schema: Dictionary,
	root_schema: Dictionary,
	instance_path: String,
	ref_stack: Dictionary
) -> Dictionary:
	if schema.has("minItems") and instance.size() < int(schema["minItems"]):
		return _invalid(instance_path, "array has too few items.")
	if schema.has("maxItems") and instance.size() > int(schema["maxItems"]):
		return _invalid(instance_path, "array has too many items.")
	if schema.get("uniqueItems", false):
		for left_index: int in range(instance.size()):
			for right_index: int in range(left_index + 1, instance.size()):
				if instance[left_index] == instance[right_index]:
					return _invalid(instance_path, "array items are not unique.")
	if schema.has("prefixItems"):
		if not schema["prefixItems"] is Array:
			return _invalid(instance_path, "prefixItems must be an array.")
		for index: int in range(mini(instance.size(), schema["prefixItems"].size())):
			var prefix_result: Dictionary = _validate_value(
				instance[index],
				schema["prefixItems"][index],
				root_schema,
				"%s/%d" % [instance_path, index],
				ref_stack
			)
			if not prefix_result.get("ok", false):
				return prefix_result
	if schema.has("items"):
		var item_schema: Variant = schema["items"]
		for index: int in range(instance.size()):
			if schema.has("prefixItems") and index < schema["prefixItems"].size():
				continue
			var item_result: Dictionary = _validate_value(
				instance[index],
				item_schema,
				root_schema,
				"%s/%d" % [instance_path, index],
				ref_stack
			)
			if not item_result.get("ok", false):
				return item_result
	if schema.has("contains"):
		var contains_count: int = 0
		for index: int in range(instance.size()):
			var contains_result: Dictionary = _validate_value(
				instance[index],
				schema["contains"],
				root_schema,
				"%s/%d" % [instance_path, index],
				ref_stack
			)
			if contains_result.get("ok", false):
				contains_count += 1
		var minimum_matches: int = int(schema.get("minContains", 1))
		var maximum_matches: int = int(schema.get("maxContains", instance.size()))
		if contains_count < minimum_matches or contains_count > maximum_matches:
			return _invalid(instance_path, "contains match count is invalid.")
	return {"ok": true}


func _validate_string(instance: String, schema: Dictionary, instance_path: String) -> Dictionary:
	if schema.has("minLength") and instance.length() < int(schema["minLength"]):
		return _invalid(instance_path, "string is too short.")
	if schema.has("maxLength") and instance.length() > int(schema["maxLength"]):
		return _invalid(instance_path, "string is too long.")
	if schema.has("pattern"):
		if typeof(schema["pattern"]) != TYPE_STRING:
			return _invalid(instance_path, "pattern must be a string.")
		var matcher: RegEx = RegEx.new()
		if matcher.compile(_pattern_for_godot_regex(schema["pattern"])) != OK:
			return _invalid(instance_path, "invalid string pattern.")
		if matcher.search(instance) == null:
			return _invalid(instance_path, "string does not match pattern.")
	return {"ok": true}


func _pattern_for_godot_regex(pattern: String) -> String:
	var converted: String = ""
	var cursor: int = 0
	while cursor < pattern.length():
		var escape_index: int = pattern.find("\\u", cursor)
		if escape_index < 0:
			converted += pattern.substr(cursor)
			break
		converted += pattern.substr(cursor, escape_index - cursor)
		var hex_digits: String = pattern.substr(escape_index + 2, 4)
		if hex_digits.length() != 4 or not hex_digits.is_valid_hex_number(false):
			return ""
		converted += "\\x{%s}" % hex_digits
		cursor = escape_index + 6
	return converted


func _validate_number(instance: Variant, schema: Dictionary, instance_path: String) -> Dictionary:
	var number: float = float(instance)
	if not is_finite(number):
		return _invalid(instance_path, "number must be finite.")
	if schema.has("minimum") and number < float(schema["minimum"]):
		return _invalid(instance_path, "number is below minimum.")
	if schema.has("maximum") and number > float(schema["maximum"]):
		return _invalid(instance_path, "number is above maximum.")
	if schema.has("exclusiveMinimum") and number <= float(schema["exclusiveMinimum"]):
		return _invalid(instance_path, "number is not above exclusiveMinimum.")
	if schema.has("exclusiveMaximum") and number >= float(schema["exclusiveMaximum"]):
		return _invalid(instance_path, "number is not below exclusiveMaximum.")
	if schema.has("multipleOf"):
		var divisor: float = float(schema["multipleOf"])
		if divisor <= 0.0 or not is_zero_approx(fposmod(number, divisor)):
			return _invalid(instance_path, "number is not a multipleOf value.")
	return {"ok": true}


func _resolve_reference(reference: String, current_root: Dictionary) -> Dictionary:
	var reference_parts: PackedStringArray = reference.split("#", true, 1)
	if reference_parts.size() == 1:
		reference_parts.append("")
	if reference_parts.size() != 2:
		return _failure("Invalid schema reference.")
	var root: Variant = current_root
	if not reference_parts[0].is_empty():
		root = _schemas_by_id.get(reference_parts[0])
	if not root is Dictionary:
		return _failure("Referenced schema resource is unavailable: %s" % reference_parts[0])
	var pointer: String = reference_parts[1]
	if pointer.is_empty():
		return {"ok": true, "schema": root, "root": root}
	if not pointer.begins_with("/"):
		return _failure("Only JSON Pointer schema fragments are supported.")
	var value: Variant = root
	for encoded_token: String in pointer.trim_prefix("/").split("/"):
		var token: String = encoded_token.replace("~1", "/").replace("~0", "~")
		if value is Dictionary and value.has(token):
			value = value[token]
		elif (
			value is Array
			and _is_array_index(token)
			and int(token) < value.size()
		):
			value = value[int(token)]
		else:
			return _failure("Referenced schema pointer does not exist: %s" % reference)
	if not value is Dictionary:
		return _failure("Referenced schema target is not an object: %s" % reference)
	return {"ok": true, "schema": value, "root": root}


func _load_schema_index() -> String:
	if _schema_index_loaded:
		return ""
	var error: String = _index_contract_schemas(CONTRACT_DIRECTORY)
	if not error.is_empty():
		return error
	_schema_index_loaded = true
	return ""


func _index_contract_schemas(directory_path: String) -> String:
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		return "Cannot open the contract directory for schema resolution."
	var files: PackedStringArray = directory.get_files()
	files.sort()
	for file_name: String in files:
		if file_name.get_extension().to_lower() != "json":
			continue
		var path: String = directory_path.path_join(file_name)
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var source: String = file.get_as_text()
		var json: JSON = JSON.new()
		if json.parse(source) != OK:
			continue
		var document: Variant = json.data
		if document is Dictionary:
			_index_schema_ids(document)
	var child_directories: PackedStringArray = directory.get_directories()
	child_directories.sort()
	for child_directory: String in child_directories:
		var child_error: String = _index_contract_schemas(
			directory_path.path_join(child_directory)
		)
		if not child_error.is_empty():
			return child_error
	return ""


func _index_schema_ids(value: Variant) -> void:
	if value is Dictionary:
		if (
			typeof(value.get("$id")) == TYPE_STRING
			and not value["$id"].is_empty()
			and value.get("$schema") == "https://json-schema.org/draft/2020-12/schema"
		):
			_schemas_by_id[value["$id"]] = value
		for child: Variant in value.values():
			_index_schema_ids(child)
	elif value is Array:
		for child: Variant in value:
			_index_schema_ids(child)


func _json_values_equal(left: Variant, right: Variant) -> bool:
	if (
		typeof(left) in [TYPE_INT, TYPE_FLOAT]
		and typeof(right) in [TYPE_INT, TYPE_FLOAT]
	):
		return float(left) == float(right)
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index: int in range(left.size()):
			if not _json_values_equal(left[index], right[index]):
				return false
		return true
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _json_values_equal(left[key], right[key]):
				return false
		return true
	return typeof(left) == typeof(right) and left == right


func _matches_type(instance: Variant, expected: Variant) -> bool:
	if expected is Array:
		for type_name: Variant in expected:
			if _matches_type(instance, type_name):
				return true
		return false
	if typeof(expected) != TYPE_STRING:
		return false
	match expected:
		"null":
			return instance == null
		"object":
			return instance is Dictionary
		"array":
			return instance is Array
		"string":
			return typeof(instance) == TYPE_STRING
		"integer":
			return (
				typeof(instance) == TYPE_INT
				or typeof(instance) == TYPE_FLOAT and is_finite(instance)
					and floor(instance) == instance
			)
		"number":
			return typeof(instance) in [TYPE_INT, TYPE_FLOAT]
		"boolean":
			return typeof(instance) == TYPE_BOOL
	return false


func _is_array_index(value: String) -> bool:
	if value.is_empty() or value.length() > 1 and value.begins_with("0"):
		return false
	for index: int in range(value.length()):
		if value.unicode_at(index) not in range(48, 58):
			return false
	return true


func _escape_pointer_token(value: String) -> String:
	return value.replace("~", "~0").replace("/", "~1")


func _invalid(instance_path: String, message: String) -> Dictionary:
	return _failure("%s: %s" % [instance_path, message])


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
