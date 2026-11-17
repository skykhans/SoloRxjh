extends RefCounted

const STRICT_JSON: Script = preload("res://scripts/strict_json.gd")
const MANIFEST_PATH: String = "res://assets/config/resources.json"
const ROOT_KEYS: PackedStringArray = ["format_version", "resources"]
const ENTRY_KEYS: PackedStringArray = ["id", "path", "type"]
const ALLOWED_RESOURCE_TYPES: PackedStringArray = [
	"AudioStreamWAV",
	"CompressedTexture2D",
	"FontFile",
	"PackedScene",
	"Shader",
]


static func validate_manifest_file(manifest_path: String = MANIFEST_PATH) -> String:
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return "无法读取正式资源清单：%s（%s）" % [
			manifest_path,
			error_string(FileAccess.get_open_error()),
		]

	var source: String = file.get_as_text()
	if STRICT_JSON.has_duplicate_object_keys(source):
		return "正式资源清单包含重复对象键：%s" % manifest_path
	var parsed: JSON = JSON.new()
	var parse_error: Error = parsed.parse(source)
	if parse_error != OK:
		return "正式资源清单格式错误：%s:%d %s" % [
			manifest_path,
			parsed.get_error_line(),
			parsed.get_error_message(),
		]

	return validate_manifest(parsed.data)


static func validate_manifest(value: Variant) -> String:
	if not value is Dictionary:
		return "正式资源清单根节点必须是对象。"
	if not _has_exact_keys(value, ROOT_KEYS):
		return "正式资源清单必须且只能包含 format_version、resources。"
	if not _is_exact_integer(value["format_version"], 1):
		return "正式资源清单 format_version 必须为整数 1。"
	if not value["resources"] is Array or value["resources"].is_empty():
		return "正式资源清单 resources 必须是非空数组。"

	var seen_ids: Dictionary = {}
	var seen_paths: Dictionary = {}
	for index: int in range(value["resources"].size()):
		var entry: Variant = value["resources"][index]
		if not entry is Dictionary or not _has_exact_keys(entry, ENTRY_KEYS):
			return "正式资源清单 resources[%d] 必须且只能包含 id、path、type。" % index
		if typeof(entry["id"]) != TYPE_STRING or not _is_resource_id(entry["id"]):
			return "正式资源清单 resources[%d].id 无效。" % index
		if typeof(entry["path"]) != TYPE_STRING or not _is_project_asset_path(entry["path"]):
			return "正式资源清单 resources[%d].path 必须位于 res://assets/ 下。" % index
		if typeof(entry["type"]) != TYPE_STRING or not ALLOWED_RESOURCE_TYPES.has(entry["type"]):
			return "正式资源清单 resources[%d].type 不受支持。" % index

		var resource_id: String = entry["id"]
		var resource_path: String = entry["path"]
		if seen_ids.has(resource_id):
			return "正式资源清单存在重复 ID：%s" % resource_id
		if seen_paths.has(resource_path):
			return "正式资源清单存在重复路径：%s" % resource_path
		seen_ids[resource_id] = true
		seen_paths[resource_path] = true

		if not FileAccess.file_exists(resource_path):
			return "正式资源文件不存在：%s" % resource_path
		var resource: Resource = ResourceLoader.load(resource_path, entry["type"])
		if resource == null:
			return "正式资源无法加载：%s" % resource_path
		if not _matches_resource_type(resource, entry["type"]):
			return "正式资源类型不匹配：%s（要求 %s，实际 %s）" % [
				resource_path,
				entry["type"],
				resource.get_class(),
			]

	return ""


static func _has_exact_keys(value: Dictionary, expected_keys: PackedStringArray) -> bool:
	if value.size() != expected_keys.size():
		return false
	for expected_key: String in expected_keys:
		if not value.has(expected_key):
			return false
	return true


static func _is_resource_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index: int in range(value.length()):
		var codepoint: int = value.unicode_at(index)
		var is_lowercase: bool = codepoint >= 97 and codepoint <= 122
		var is_digit: bool = codepoint >= 48 and codepoint <= 57
		if not (is_lowercase or is_digit or codepoint == 95):
			return false
	return true


static func _is_exact_integer(value: Variant, expected: int) -> bool:
	var value_type: int = typeof(value)
	if value_type == TYPE_INT:
		return value == expected
	if value_type != TYPE_FLOAT:
		return false
	var numeric_value: float = value
	return is_finite(numeric_value) and floorf(numeric_value) == numeric_value and numeric_value == expected


static func _is_project_asset_path(value: String) -> bool:
	if not value.begins_with("res://assets/"):
		return false
	for segment: String in value.trim_prefix("res://").split("/"):
		if segment.is_empty() or segment == "." or segment == "..":
			return false
	return true


static func _matches_resource_type(resource: Resource, expected_type: String) -> bool:
	match expected_type:
		"AudioStreamWAV":
			return resource is AudioStreamWAV
		"CompressedTexture2D":
			return resource is CompressedTexture2D
		"FontFile":
			return resource is FontFile
		"PackedScene":
			return resource is PackedScene
		"Shader":
			return resource is Shader
	return false
