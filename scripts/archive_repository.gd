class_name ArchiveRepository
extends RefCounted

const ARCHIVE_SCHEMA_PATH: String = "res://docs/contracts/新空档案.schema.json"
const METADATA_SCHEMA_PATH: String = "res://docs/contracts/档案元数据投影.schema.json"
const METADATA_OWNER_PATH: String = "res://docs/contracts/档案元数据与设置.v1.json"
const APP_DATA_DIRECTORY_NAME: String = "SoloRxjh"
const MAX_ARCHIVES: int = 3

var _profiles_directory: String
var _profiles_directory_error: String = ""
var _pending_profile_id: String
var _pending_profile_name: String


func _init(profiles_directory: String = "") -> void:
	_profiles_directory = profiles_directory
	if not _profiles_directory.is_empty():
		return

	_profiles_directory = default_profiles_directory(OS.get_environment("LOCALAPPDATA"))
	if _profiles_directory.is_empty():
		_profiles_directory_error = "无法确定档案目录：缺少LOCALAPPDATA。"


static func default_profiles_directory(local_app_data: String) -> String:
	if local_app_data.is_empty():
		return ""
	return local_app_data.path_join(APP_DATA_DIRECTORY_NAME).path_join("profiles")


func list_profiles() -> Dictionary:
	var directory_error: String = _ensure_profiles_directory()
	if not directory_error.is_empty():
		return _failure(directory_error)

	var directory_lease: WindowsArchiveLease = WindowsArchiveLease.new()
	var lock_result: Dictionary = directory_lease.try_acquire(_profiles_directory)
	if not lock_result.get("ok", false):
		return _failure("无法读取档案目录：%s" % lock_result.get("error", "unknown"))

	var result: Dictionary = _scan_profiles(directory_lease)
	directory_lease.release()
	return result


func create_profile(raw_name: String) -> Dictionary:
	var name_result: Dictionary = WindowsArchiveLease.new().normalize_profile_name(raw_name)
	if not name_result.get("ok", false):
		return _failure("档案名称无效：%s" % name_result.get("error", "unknown"))
	var profile_name: String = name_result["profile_name"]
	if not _pending_profile_id.is_empty() and profile_name != _pending_profile_name:
		return _failure("上一笔档案创建结果尚未确认，请使用同一名称重试。")

	var directory_error: String = _ensure_profiles_directory()
	if not directory_error.is_empty():
		return _failure(directory_error)

	var directory_lease: WindowsArchiveLease = WindowsArchiveLease.new()
	var lock_result: Dictionary = directory_lease.try_acquire(_profiles_directory)
	if not lock_result.get("ok", false):
		return _failure("无法创建档案：%s" % lock_result.get("error", "unknown"))

	if _pending_profile_id.is_empty():
		var catalog: Dictionary = _scan_profiles(directory_lease)
		if not catalog.get("ok", false):
			directory_lease.release()
			return catalog
		if not catalog.get("all_valid", false):
			directory_lease.release()
			return _failure("存在无法完整验证的档案，已停止新建。")
		if catalog["profiles"].size() >= MAX_ARCHIVES:
			directory_lease.release()
			return _failure("档案数量已达上限（%d）。" % MAX_ARCHIVES)
		for profile: Dictionary in catalog["profiles"]:
			if profile["comparison_key"] == name_result["comparison_key"]:
				directory_lease.release()
				return _failure("档案名称已被使用。")

		var random_bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
		if random_bytes.size() != 16:
			directory_lease.release()
			return _failure("系统随机数生成失败，档案未创建。")
		_pending_profile_id = "profile_" + random_bytes.hex_encode()
		_pending_profile_name = profile_name

	var result: Dictionary = _continue_pending_create(
		directory_lease,
		profile_name,
		name_result["comparison_key"]
	)
	directory_lease.release()
	if result.get("ok", false):
		_pending_profile_id = ""
		_pending_profile_name = ""
	return result


func _continue_pending_create(
		directory_lease: WindowsArchiveLease,
		profile_name: String,
		comparison_key: String
) -> Dictionary:
	var catalog: Dictionary = _scan_profiles(directory_lease)
	if not catalog.get("ok", false):
		return catalog
	if not catalog.get("all_valid", false):
		return _failure("存在无法完整验证的档案，已停止新建。")

	var candidate: Dictionary = _build_empty_profile(_pending_profile_id, profile_name)
	if not candidate.get("ok", false):
		return _failure(candidate["error"])
	var target_name: String = "%s.json" % _pending_profile_id

	for profile: Dictionary in catalog["profiles"]:
		if profile["file_name"].nocasecmp_to(target_name) == 0:
			if profile["file_name"] == target_name and profile["data"] == candidate["data"]:
				return {
					"ok": true,
					"profile": profile,
					"recovered": true,
				}
			return _failure("档案ID发生冲突，原文件已保留。")
		if profile["comparison_key"] == comparison_key:
			return _failure("档案名称已被使用。")

	if catalog["profiles"].size() >= MAX_ARCHIVES:
		return _failure("档案数量已达上限（%d）。" % MAX_ARCHIVES)

	var profile_lease: WindowsArchiveLease = WindowsArchiveLease.new()
	var profile_lock: Dictionary = profile_lease.try_acquire(_profiles_directory, _pending_profile_id)
	if not profile_lock.get("ok", false):
		profile_lease.release()
		return _failure("无法取得新档案租约：%s" % profile_lock.get("error", "unknown"))

	var serialized: String = JSON.stringify(candidate["data"], "\t", true, true) + "\n"
	var candidate_bytes: PackedByteArray = serialized.to_utf8_buffer()
	var publish_result: Dictionary = profile_lease.publish_bytes(
		_profiles_directory,
		".%s.create.tmp" % _pending_profile_id,
		target_name,
		candidate_bytes,
		false
	)
	profile_lease.release()

	if not publish_result.get("ok", false):
		var after_publish: Dictionary = _read_published_candidate(directory_lease, target_name)
		if after_publish.get("ok", false) and after_publish.get("data") == candidate["data"]:
			return {
				"ok": true,
				"profile": after_publish,
				"recovered": true,
			}
		return _failure("档案发布失败，保留同次创建ID：%s" % publish_result.get("error", "unknown"))

	var published: Dictionary = _read_published_candidate(directory_lease, target_name)
	if not published.get("ok", false):
		return _failure("正式档案发布后无法验证：%s" % published.get("error", "unknown"))
	if published["data"] != candidate["data"]:
		return _failure("正式档案内容与候选不一致，未报告成功。")
	return {
		"ok": true,
		"profile": published,
		"recovered": false,
	}


func _scan_profiles(directory_lease: WindowsArchiveLease) -> Dictionary:
	var enumeration: Dictionary = directory_lease.enumerate_profile_candidates(_profiles_directory)
	if not enumeration.get("ok", false):
		return _failure("无法枚举档案目录：%s" % enumeration.get("error", "unknown"))

	var profiles: Array[Dictionary] = []
	for entry: Dictionary in enumeration.get("entries", []):
		var file_name: String = entry.get("name", "")
		var profile: Dictionary = {
			"file_name": file_name,
			"valid": false,
			"error": "",
		}
		if entry.get("is_directory", false) or entry.get("is_reparse_point", false):
			profile["error"] = "候选不是普通档案文件"
		else:
			var read_result: Dictionary = directory_lease.read_profile_candidate(
				_profiles_directory,
				file_name
			)
			if not read_result.get("ok", false):
				profile["error"] = "档案不可读：%s" % read_result.get("error", "unknown")
			else:
				var json: JSON = JSON.new()
				var parse_error: Error = json.parse(read_result["bytes"].get_string_from_utf8())
				if parse_error != OK:
					profile["error"] = "JSON错误：%s" % json.get_error_message()
				elif not json.data is Dictionary:
					profile["error"] = "档案根节点必须是对象"
				else:
					var validation: Dictionary = _validate_profile(json.data, file_name)
					profile.merge(validation, true)
		profiles.push_back(profile)

	var names: Dictionary = {}
	for index: int in range(profiles.size()):
		var profile: Dictionary = profiles[index]
		if not profile.get("valid", false):
			continue
		var comparison_key: String = profile["comparison_key"]
		if names.has(comparison_key):
			profiles[index]["valid"] = false
			profiles[index]["error"] = "档案名称重复"
			profiles[names[comparison_key]]["valid"] = false
			profiles[names[comparison_key]]["error"] = "档案名称重复"
		else:
			names[comparison_key] = index

	var all_valid: bool = true
	for profile: Dictionary in profiles:
		all_valid = all_valid and profile.get("valid", false)
	return {
		"ok": true,
		"profiles": profiles,
		"all_valid": all_valid,
		"can_create": all_valid and profiles.size() < MAX_ARCHIVES,
	}


func _validate_profile(profile: Dictionary, file_name: String) -> Dictionary:
	var schema_result: Dictionary = _read_json(ARCHIVE_SCHEMA_PATH)
	if not schema_result.get("ok", false):
		return _failure(schema_result["error"])
	var metadata_result: Dictionary = _read_json(METADATA_OWNER_PATH)
	if not metadata_result.get("ok", false):
		return _failure(metadata_result["error"])

	var required: Array = schema_result["data"].get("required", [])
	if required.size() != 75 or profile.size() != required.size():
		return _failure("档案字段数不符合完整空档案合同")
	for field: String in required:
		if not profile.has(field):
			return _failure("档案缺少字段：%s" % field)

	var profile_id: String = file_name.substr(0, file_name.length() - 5)
	if file_name != "%s.json" % profile_id or not _is_profile_id(profile_id):
		return _failure("档案文件名不符合profile_id")
	if profile.get("profile_id") != profile_id:
		return _failure("profile_id与档案文件名不一致")
	var revision_type: int = typeof(profile.get("revision"))
	if revision_type != TYPE_INT and revision_type != TYPE_FLOAT:
		return _failure("档案revision无效")
	var revision_value: float = float(profile["revision"])
	if (
		not is_finite(revision_value)
		or floor(revision_value) != revision_value
		or revision_value < 1.0
		or revision_value > 9007199254740991.0
	):
		return _failure("档案revision无效")

	var name_result: Dictionary = WindowsArchiveLease.new().normalize_profile_name(
		str(profile.get("profile_name", ""))
	)
	if not name_result.get("ok", false) or name_result["profile_name"] != profile["profile_name"]:
		return _failure("档案显示名不是有效规范名")
	var settings_error: String = _validate_settings(
		profile.get("settings"),
		metadata_result["data"]["default_settings"]
	)
	if not settings_error.is_empty():
		return _failure("档案settings无效：%s" % settings_error)

	var template_result: Dictionary = _build_empty_profile(
		profile_id,
		profile["profile_name"]
	)
	if not template_result.get("ok", false):
		return _failure(template_result["error"])
	for field: String in required:
		if field in ["profile_id", "profile_name", "revision", "settings"]:
			continue
		if profile[field] != template_result["data"][field]:
			return _failure("当前档案不属于已实现的空档案格式：%s" % field)

	return {
		"ok": true,
		"valid": true,
		"error": "",
		"file_name": file_name,
		"profile_id": profile_id,
		"profile_name": profile["profile_name"],
		"comparison_key": name_result["comparison_key"],
		"revision": profile["revision"],
		"character_count": profile["characters"].size(),
		"data": profile,
	}


func _validate_settings(settings: Variant, defaults: Dictionary) -> String:
	if not settings is Dictionary or settings.size() != defaults.size():
		return "键数"
	for key: String in defaults:
		if not settings.has(key):
			return key
	for key: String in ["master_volume", "music_volume", "sfx_volume", "ui_volume"]:
		if not _finite_number_in_range(settings[key], 0.0, 1.0):
			return key
	if not _finite_number_in_range(settings["camera_distance"], 3.0, 12.0):
		return "camera_distance"
	if not settings["window_mode"] in ["windowed", "borderless_fullscreen"]:
		return "window_mode"
	var resolution: Variant = settings["window_resolution"]
	if not resolution is Array or resolution.size() != 2:
		return "window_resolution"
	var resolution_matches_allowed_size: bool = false
	for allowed_size: Array in [[1280, 720], [1600, 900], [1920, 1080], [2560, 1440]]:
		if (
			typeof(resolution[0]) in [TYPE_INT, TYPE_FLOAT]
			and typeof(resolution[1]) in [TYPE_INT, TYPE_FLOAT]
			and float(resolution[0]) == float(allowed_size[0])
			and float(resolution[1]) == float(allowed_size[1])
		):
			resolution_matches_allowed_size = true
			break
	if not resolution_matches_allowed_size:
		return "window_resolution"
	if not settings["graphics_preset"] in ["low", "medium", "high"]:
		return "graphics_preset"
	if typeof(settings["vsync_enabled"]) != TYPE_BOOL:
		return "vsync_enabled"
	return ""


func _finite_number_in_range(value: Variant, minimum: float, maximum: float) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var numeric_value: float = float(value)
	return is_finite(numeric_value) and numeric_value >= minimum and numeric_value <= maximum


func _build_empty_profile(profile_id: String, profile_name: String) -> Dictionary:
	var schema_result: Dictionary = _read_json(ARCHIVE_SCHEMA_PATH)
	if not schema_result.get("ok", false):
		return schema_result
	var metadata_schema_result: Dictionary = _read_json(METADATA_SCHEMA_PATH)
	if not metadata_schema_result.get("ok", false):
		return metadata_schema_result
	var metadata_owner_result: Dictionary = _read_json(METADATA_OWNER_PATH)
	if not metadata_owner_result.get("ok", false):
		return metadata_owner_result

	var schema: Dictionary = schema_result["data"]
	var properties: Dictionary = schema.get("properties", {})
	var metadata_properties: Dictionary = metadata_schema_result["data"].get("properties", {})
	var metadata_owner: Dictionary = metadata_owner_result["data"]
	var profile: Dictionary = {}
	var required: Array = schema.get("required", [])
	if required.size() != 75 or properties.size() != required.size():
		return _failure("新空档案合同字段数量不是75")

	for field: String in required:
		var property: Dictionary = properties.get(field, {})
		if property.is_empty():
			return _failure("新空档案合同缺少字段定义：%s" % field)
		if field == "profile_id":
			profile[field] = profile_id
		elif field == "profile_name":
			profile[field] = profile_name
		elif field == "settings":
			profile[field] = metadata_owner["default_settings"].duplicate(true)
		elif field in ["schema_version", "content_version"]:
			var metadata_property: Dictionary = metadata_properties.get(field, {})
			if not metadata_property.has("const"):
				return _failure("元数据owner未定义初值：%s" % field)
			profile[field] = metadata_property["const"]
		elif property.has("const"):
			profile[field] = _copy_value(property["const"])
		elif property.get("maxItems") == 0:
			profile[field] = []
		elif property.get("maxProperties") == 0:
			profile[field] = {}
		else:
			return _failure("新空档案字段没有完整初值：%s" % field)
	return {
		"ok": true,
		"data": profile,
	}


func _read_published_candidate(
		directory_lease: WindowsArchiveLease,
		file_name: String
) -> Dictionary:
	var read_result: Dictionary = directory_lease.read_profile_candidate(
		_profiles_directory,
		file_name
	)
	if not read_result.get("ok", false):
		return _failure(read_result.get("error", "档案回读失败"))
	var json: JSON = JSON.new()
	var parse_error: Error = json.parse(read_result["bytes"].get_string_from_utf8())
	if parse_error != OK or not json.data is Dictionary:
		return _failure("正式档案无法解析")
	return _validate_profile(json.data, file_name)


func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("无法读取正式合同：%s" % path)
	var json: JSON = JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	if parse_error != OK or not json.data is Dictionary:
		return _failure("正式合同JSON错误：%s" % path)
	return {
		"ok": true,
		"data": json.data,
	}


func _ensure_profiles_directory() -> String:
	if not _profiles_directory_error.is_empty():
		return _profiles_directory_error
	if DirAccess.dir_exists_absolute(_profiles_directory):
		return ""
	var error: Error = DirAccess.make_dir_recursive_absolute(_profiles_directory)
	if error != OK and not DirAccess.dir_exists_absolute(_profiles_directory):
		return "无法创建档案目录：%s" % error_string(error)
	return ""


func _is_profile_id(profile_id: String) -> bool:
	if profile_id.length() != 40 or not profile_id.begins_with("profile_"):
		return false
	for index: int in range(8, profile_id.length()):
		var codepoint: int = profile_id.unicode_at(index)
		if not (codepoint in range(48, 58) or codepoint in range(97, 103)):
			return false
	return true


func _copy_value(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value


func _failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"error": error,
	}
