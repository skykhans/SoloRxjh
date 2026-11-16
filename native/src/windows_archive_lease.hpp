#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <windows.h>

#include <string>

namespace godot {

class WindowsArchiveLease final : public RefCounted {
	GDCLASS(WindowsArchiveLease, RefCounted)

	HANDLE lock_file_ = INVALID_HANDLE_VALUE;
	OVERLAPPED lock_range_ = {};
	std::wstring directory_identity_;
	String profile_id_;
	String last_error_;

	static bool is_profile_id(const String &p_profile_id);
	static bool is_leaf_name(const String &p_name);
	static bool is_candidate_name(const String &p_name);
	static bool has_forbidden_name_codepoint(const String &p_name);
	static bool get_directory_identity(const String &p_directory, std::wstring &r_identity, String &r_error);
	static bool validate_publish_target(const std::wstring &p_path, bool p_replace, String &r_error);
	bool directory_matches_lease(const String &p_directory, String &r_error) const;

protected:
	static void _bind_methods();

public:
	~WindowsArchiveLease() override;

	Dictionary try_acquire(const String &p_profiles_directory, const String &p_profile_id = String());
	Dictionary enumerate_profile_candidates(const String &p_profiles_directory) const;
	Dictionary read_profile_candidate(const String &p_profiles_directory, const String &p_file_name) const;
	Dictionary normalize_profile_name(const String &p_profile_name) const;
	Dictionary publish_bytes(
			const String &p_profiles_directory,
			const String &p_temporary_name,
			const String &p_target_name,
			const PackedByteArray &p_contents,
			bool p_replace);
	void release();

	bool is_acquired() const;
	String get_last_error() const;
};

} // namespace godot
