extends SceneTree

const ARCHIVE_REPOSITORY: Script = preload("res://scripts/archive_repository.gd")
const ARCHIVE_FILE_LEASE: Script = preload("res://scripts/archive_file_lease.gd")
const UNICODE_NORMALIZER: Script = preload("res://scripts/unicode15_normalizer.gd")


func _initialize() -> void:
	var expected_profiles_directory: String = "C:/Users/Tester/AppData/Local/SoloRxjh/profiles"
	if not _require(
		ARCHIVE_REPOSITORY.default_profiles_directory("C:/Users/Tester/AppData/Local")
			== expected_profiles_directory
			and ARCHIVE_REPOSITORY.default_profiles_directory("").is_empty(),
		"Default profile directory does not match the Windows storage contract."
	):
		return

	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if not _require(arguments.size() == 1, "Expected an isolated test root path."):
		return
	var profiles_directory: String = arguments[0].path_join("profiles")
	var repository: RefCounted = ARCHIVE_REPOSITORY.new(profiles_directory)

	var normalized_name: Dictionary = UNICODE_NORMALIZER.normalize_profile_name("  e\u0301乙  ")
	var sharp_s_name: Dictionary = UNICODE_NORMALIZER.normalize_profile_name("ß甲")
	var ss_name: Dictionary = UNICODE_NORMALIZER.normalize_profile_name("SS甲")
	var final_sigma_name: Dictionary = UNICODE_NORMALIZER.normalize_profile_name("ς乙")
	var sigma_name: Dictionary = UNICODE_NORMALIZER.normalize_profile_name("σ乙")
	var reordered_marks_name: Dictionary = UNICODE_NORMALIZER.normalize_profile_name("a\u0315\u0300乙")
	var hangul_name: Dictionary = UNICODE_NORMALIZER.normalize_profile_name("가乙")
	var compatibility_name: Dictionary = UNICODE_NORMALIZER.normalize_profile_name("ﬃ甲")
	var compatibility_fold: Dictionary = UNICODE_NORMALIZER.normalize_profile_name("ffi甲")
	if not _require(
		normalized_name.get("ok", false)
			and normalized_name.get("profile_name") == "é乙"
			and sharp_s_name.get("ok", false)
			and sharp_s_name.get("comparison_key") == ss_name.get("comparison_key")
			and final_sigma_name.get("comparison_key") == sigma_name.get("comparison_key")
			and reordered_marks_name.get("profile_name") == "à\u0315乙"
			and hangul_name.get("profile_name") == "가乙"
			and compatibility_name.get("profile_name") == "ﬃ甲"
			and compatibility_name.get("comparison_key") == compatibility_fold.get("comparison_key")
			and UNICODE_NORMALIZER.normalize_profile_name("  e\u0301乙  ").get("profile_name")
				== normalized_name.get("profile_name")
			and UNICODE_NORMALIZER.normalize_profile_name("甲\n乙").get("ok", true) == false,
		"Profile name canonicalization failed."
	):
		return

	var empty_catalog: Dictionary = repository.list_profiles()
	if not _require(
		empty_catalog.get("ok", false)
			and empty_catalog.get("all_valid", false)
			and empty_catalog.get("profiles", []).is_empty(),
		"An empty profile directory was not accepted: %s" % empty_catalog
	):
		return

	var first: Dictionary = repository.create_profile("ß甲")
	if not _require(first.get("ok", false), "First profile creation failed: %s" % first):
		return
	if not _require(
		first["profile"]["data"].size() == 75
			and first["profile"]["data"]["revision"] == 1
			and first["profile"]["data"]["settings"]["master_volume"] == 0.7
			and first["profile"]["data"]["characters"].is_empty()
			and first["profile"]["data"]["worlds"].is_empty(),
		"Created profile does not match the complete empty-profile initial state."
	):
		return

	var held_profile_lease: Variant = ARCHIVE_FILE_LEASE.new()
	var held_lock_result: Dictionary = held_profile_lease.try_acquire(
		profiles_directory,
		first["profile"]["profile_id"]
	)
	if not _require(held_lock_result.get("ok", false), "Could not hold the profile lease fixture."):
		return
	var blocked_rename: Dictionary = repository.rename_profile(
		first["profile"]["profile_id"],
		"ß甲",
		1,
		"锁定改名"
	)
	var blocked_delete: Dictionary = repository.delete_profile(
		first["profile"]["profile_id"],
		"ß甲",
		1,
		"ß甲"
	)
	var lease_released: bool = held_profile_lease.release()
	if not _require(
		not blocked_rename.get("ok", false)
			and not blocked_delete.get("ok", false)
			and lease_released,
		"A profile with an active lease was modified or left the directory lease held."
	):
		return

	var unchanged_rename: Dictionary = repository.rename_profile(
		first["profile"]["profile_id"],
		"ß甲",
		1,
		"  ß甲  "
	)
	if not _require(
		unchanged_rename.get("ok", false)
			and not unchanged_rename.get("changed", true)
			and unchanged_rename["profile"]["revision"] == 1,
		"A no-op rename changed the profile."
	):
		return

	var expected_renamed_data: Dictionary = first["profile"]["data"].duplicate(true)
	expected_renamed_data["profile_name"] = "SS甲"
	expected_renamed_data["revision"] = 2.0
	var rename_temporary_path: String = profiles_directory.path_join(
		".%s.rename.tmp" % first["profile"]["profile_id"]
	)
	var rename_temporary: FileAccess = FileAccess.open(rename_temporary_path, FileAccess.WRITE)
	if not _require(
		rename_temporary != null,
		"Could not create a matching interrupted rename fixture."
	):
		return
	rename_temporary.store_string(JSON.stringify(expected_renamed_data, "\t", true, true) + "\n")
	rename_temporary.close()
	var renamed: Dictionary = repository.rename_profile(
		first["profile"]["profile_id"],
		"ß甲",
		1,
		" SS甲 "
	)
	if not _require(
		renamed.get("ok", false)
			and renamed.get("changed", false)
			and not renamed.get("recovered", true)
			and renamed["profile"]["data"] == expected_renamed_data
			and not FileAccess.file_exists(rename_temporary_path),
		"Rename did not preserve the complete profile except its name and revision."
	):
		return
	var recovered_rename: Dictionary = repository.rename_profile(
		first["profile"]["profile_id"],
		"ß甲",
		1,
		"SS甲"
	)
	if not _require(
		recovered_rename.get("ok", false)
			and recovered_rename.get("recovered", false)
			and recovered_rename["profile"]["revision"] == 2,
		"An already committed rename was not recognized without incrementing revision."
	):
		return
	var stale_rename: Dictionary = repository.rename_profile(
		first["profile"]["profile_id"],
		"ß甲",
		1,
		"旧修订"
	)
	if not _require(not stale_rename.get("ok", false), "A stale profile rename was accepted."):
		return

	var duplicate: Dictionary = repository.create_profile("SS甲")
	if not _require(
		not duplicate.get("ok", false),
		"A casefold-equivalent profile name was accepted."
	):
		return

	var second: Dictionary = repository.create_profile("丙丁")
	var duplicate_rename: Dictionary = repository.rename_profile(
		first["profile"]["profile_id"],
		"SS甲",
		2,
		"丙丁"
	)
	if not _require(
		second.get("ok", false) and not duplicate_rename.get("ok", false),
		"A profile rename accepted a name owned by another profile."
	):
		return
	var after_duplicate_rename: Dictionary = repository.list_profiles()
	var first_after_duplicate: Dictionary = {}
	for profile: Dictionary in after_duplicate_rename.get("profiles", []):
		if profile.get("profile_id") == first["profile"]["profile_id"]:
			first_after_duplicate = profile
	if not _require(
		first_after_duplicate.get("profile_name") == "SS甲"
			and first_after_duplicate.get("revision") == 2,
		"A rejected duplicate rename changed the target profile."
	):
		return
	var third: Dictionary = repository.create_profile("戊己")
	if not _require(
		third.get("ok", false),
		"Profile capacity could not be filled: %s, %s" % [second, third]
	):
		return
	var over_capacity: Dictionary = repository.create_profile("庚辛")
	if not _require(not over_capacity.get("ok", false), "A fourth profile was accepted."):
		return

	var profile_file: FileAccess = FileAccess.open(
		profiles_directory.path_join("broken.json"),
		FileAccess.WRITE
	)
	if not _require(profile_file != null, "Could not create an isolated corrupt-candidate fixture."):
		return
	profile_file.store_string("{")
	profile_file.close()

	var corrupt_catalog: Dictionary = repository.list_profiles()
	var blocked_create: Dictionary = repository.create_profile("壬癸")
	if not _require(
		corrupt_catalog.get("all_valid", true) == false
			and not blocked_create.get("ok", false)
			and corrupt_catalog["profiles"].size() == 4,
		"A corrupt JSON candidate did not occupy capacity and block writes."
	):
		return
	var blocked_rename_by_corrupt_candidate: Dictionary = repository.rename_profile(
		first["profile"]["profile_id"],
		"SS甲",
		2,
		"新名字"
	)
	var blocked_delete_by_corrupt_candidate: Dictionary = repository.delete_profile(
		first["profile"]["profile_id"],
		"SS甲",
		2,
		"SS甲"
	)
	if not _require(
		not blocked_rename_by_corrupt_candidate.get("ok", false)
			and not blocked_delete_by_corrupt_candidate.get("ok", false),
		"A corrupt candidate did not block profile mutation."
	):
		return

	var corrupt_path: String = profiles_directory.path_join("broken.json")
	if not _require(
		DirAccess.remove_absolute(corrupt_path) == OK
			and not FileAccess.file_exists(corrupt_path),
		"Could not remove the isolated corrupt profile fixture."
	):
		return

	var name_mismatch_delete: Dictionary = repository.delete_profile(
		first["profile"]["profile_id"],
		"SS甲",
		2,
		"ss甲"
	)
	var stale_delete: Dictionary = repository.delete_profile(
		first["profile"]["profile_id"],
		"SS甲",
		1,
		"SS甲"
	)
	if not _require(
		not name_mismatch_delete.get("ok", false)
			and not stale_delete.get("ok", false)
			and FileAccess.file_exists(
				profiles_directory.path_join(first["profile"]["profile_id"] + ".json")
			),
		"A mismatched confirmation or stale revision changed the profile."
	):
		return

	var deleted: Dictionary = repository.delete_profile(
		first["profile"]["profile_id"],
		"SS甲",
		2,
		"SS甲"
	)
	var remaining: Dictionary = repository.list_profiles()
	if not _require(
		deleted.get("ok", false)
			and deleted.get("deleted", false)
			and remaining.get("ok", false)
			and remaining.get("all_valid", false)
			and remaining.get("profiles", []).size() == 2
			and not FileAccess.file_exists(
				profiles_directory.path_join(first["profile"]["profile_id"] + ".json")
			),
		"Confirmed profile deletion did not remove only the selected empty archive."
	):
		return

	print("P2 empty profile lifecycle smoke test passed.")
	quit(0)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false
