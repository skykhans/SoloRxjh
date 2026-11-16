#include "windows_archive_lease.hpp"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <limits>
#include <vector>

#pragma comment(lib, "Normaliz.lib")

namespace godot {

namespace {

Dictionary make_result(bool p_ok, const String &p_error = String()) {
	Dictionary result;
	result["ok"] = p_ok;
	result["error"] = p_error;
	return result;
}

std::wstring to_wide_string(const String &p_value) {
	CharWideString wide_value = p_value.wide_string();
	return std::wstring(wide_value.get_data());
}

String from_wide_string(const std::wstring &p_value) {
	return String::utf16(reinterpret_cast<const char16_t *>(p_value.data()), static_cast<int64_t>(p_value.size()));
}

bool is_json_candidate(const std::wstring &p_name) {
	if (p_name.size() < 5) {
		return false;
	}
	return CompareStringOrdinal(
					p_name.data() + p_name.size() - 5,
					5,
					L".json",
					5,
					TRUE) == CSTR_EQUAL;
}

bool normalize_windows_text(const std::wstring &p_input, std::wstring &r_output) {
	const int required_length = NormalizeString(
			NormalizationC,
			p_input.c_str(),
			static_cast<int>(p_input.size()),
			nullptr,
			0);
	if (required_length <= 0) {
		return false;
	}

	std::vector<wchar_t> buffer(static_cast<size_t>(required_length));
	const int written = NormalizeString(
			NormalizationC,
			p_input.c_str(),
			static_cast<int>(p_input.size()),
			buffer.data(),
			required_length);
	if (written <= 0 || written > required_length) {
		return false;
	}
	r_output.assign(buffer.data(), static_cast<size_t>(written));
	return true;
}

} // namespace

bool WindowsArchiveLease::is_profile_id(const String &p_profile_id) {
	if (p_profile_id.length() != 40 || !p_profile_id.begins_with("profile_")) {
		return false;
	}
	for (int64_t index = 8; index < p_profile_id.length(); ++index) {
		const char32_t codepoint = p_profile_id[index];
		if (!((codepoint >= '0' && codepoint <= '9') || (codepoint >= 'a' && codepoint <= 'f'))) {
			return false;
		}
	}
	return true;
}

bool WindowsArchiveLease::is_leaf_name(const String &p_name) {
	if (p_name.is_empty() || p_name == "." || p_name == ".." || p_name.ends_with(".") || p_name.ends_with(" ")) {
		return false;
	}
	for (int64_t index = 0; index < p_name.length(); ++index) {
		const char32_t codepoint = p_name[index];
		if (codepoint < 0x20 || codepoint > 0x7e || codepoint == '/' || codepoint == '\\' || codepoint == ':') {
			return false;
		}
	}
	return true;
}

bool WindowsArchiveLease::is_candidate_name(const String &p_name) {
	if (p_name.is_empty() || p_name == "." || p_name == ".." || p_name.ends_with(".") || p_name.ends_with(" ")) {
		return false;
	}
	for (int64_t index = 0; index < p_name.length(); ++index) {
		const char32_t codepoint = p_name[index];
		if (codepoint < 0x20 || codepoint == '/' || codepoint == '\\' || codepoint == ':') {
			return false;
		}
	}
	return true;
}

bool WindowsArchiveLease::has_forbidden_name_codepoint(const String &p_name) {
	for (int64_t index = 0; index < p_name.length(); ++index) {
		const char32_t codepoint = p_name[index];
		if (codepoint < 0x20 ||
				(codepoint >= 0x7f && codepoint <= 0x9f) ||
				(codepoint >= 0xd800 && codepoint <= 0xdfff)) {
			return true;
		}
	}
	return false;
}

bool WindowsArchiveLease::get_directory_identity(const String &p_directory, std::wstring &r_identity, String &r_error) {
	CharWideString directory_path = p_directory.wide_string();
	HANDLE directory_handle = CreateFileW(
			directory_path.get_data(),
			FILE_READ_ATTRIBUTES,
			FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
			nullptr,
			OPEN_EXISTING,
			FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
			nullptr);
	if (directory_handle == INVALID_HANDLE_VALUE) {
		r_error = "directory_open_failed:" + String::num_int64(GetLastError());
		return false;
	}

	BY_HANDLE_FILE_INFORMATION information = {};
	if (GetFileInformationByHandle(directory_handle, &information) == 0) {
		r_error = "directory_info_failed:" + String::num_int64(GetLastError());
		CloseHandle(directory_handle);
		return false;
	}
	if ((information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
			(information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
		r_error = "directory_type_mismatch";
		CloseHandle(directory_handle);
		return false;
	}

	const DWORD required_length = GetFinalPathNameByHandleW(
			directory_handle,
			nullptr,
			0,
			FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
	if (required_length == 0) {
		r_error = "directory_identity_failed:" + String::num_int64(GetLastError());
		CloseHandle(directory_handle);
		return false;
	}

	std::vector<wchar_t> path_buffer(static_cast<size_t>(required_length) + 1);
	const DWORD path_length = GetFinalPathNameByHandleW(
			directory_handle,
			path_buffer.data(),
			static_cast<DWORD>(path_buffer.size()),
			FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
	const DWORD error_code = path_length == 0 ? GetLastError() : ERROR_SUCCESS;
	CloseHandle(directory_handle);
	if (path_length == 0 || path_length >= path_buffer.size()) {
		r_error = "directory_identity_failed:" + String::num_int64(error_code);
		return false;
	}

	r_identity.assign(path_buffer.data(), path_length);
	while (r_identity.size() > 4 && (r_identity.back() == L'\\' || r_identity.back() == L'/')) {
		r_identity.pop_back();
	}
	return true;
}

bool WindowsArchiveLease::validate_publish_target(const std::wstring &p_path, bool p_replace, String &r_error) {
	const DWORD attributes = GetFileAttributesW(p_path.c_str());
	if (attributes == INVALID_FILE_ATTRIBUTES) {
		const DWORD error_code = GetLastError();
		if (!p_replace && (error_code == ERROR_FILE_NOT_FOUND || error_code == ERROR_PATH_NOT_FOUND)) {
			return true;
		}
		r_error = (p_replace ? "publish_target_missing:" : "publish_target_check_failed:") + String::num_int64(error_code);
		return false;
	}
	if ((attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0) {
		r_error = "publish_target_type_mismatch";
		return false;
	}
	if (!p_replace) {
		r_error = "publish_target_exists";
		return false;
	}
	return true;
}

bool WindowsArchiveLease::directory_matches_lease(const String &p_directory, String &r_error) const {
	if (lock_file_ == INVALID_HANDLE_VALUE) {
		r_error = "lease_not_acquired";
		return false;
	}

	std::wstring requested_identity;
	if (!get_directory_identity(p_directory, requested_identity, r_error)) {
		return false;
	}
	if (CompareStringOrdinal(
				requested_identity.c_str(),
				static_cast<int>(requested_identity.size()),
				directory_identity_.c_str(),
				static_cast<int>(directory_identity_.size()),
				TRUE) != CSTR_EQUAL) {
		r_error = "lease_directory_mismatch";
		return false;
	}
	return true;
}

void WindowsArchiveLease::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("try_acquire", "profiles_directory", "profile_id"),
			&WindowsArchiveLease::try_acquire,
			DEFVAL(String()));
	ClassDB::bind_method(
			D_METHOD("enumerate_profile_candidates", "profiles_directory"),
			&WindowsArchiveLease::enumerate_profile_candidates);
	ClassDB::bind_method(
			D_METHOD("read_profile_candidate", "profiles_directory", "file_name"),
			&WindowsArchiveLease::read_profile_candidate);
	ClassDB::bind_method(
			D_METHOD("normalize_profile_name", "profile_name"),
			&WindowsArchiveLease::normalize_profile_name);
	ClassDB::bind_method(
			D_METHOD("publish_bytes", "profiles_directory", "temporary_name", "target_name", "contents", "replace"),
			&WindowsArchiveLease::publish_bytes);
	ClassDB::bind_method(D_METHOD("release"), &WindowsArchiveLease::release);
	ClassDB::bind_method(D_METHOD("is_acquired"), &WindowsArchiveLease::is_acquired);
	ClassDB::bind_method(D_METHOD("get_last_error"), &WindowsArchiveLease::get_last_error);
}

WindowsArchiveLease::~WindowsArchiveLease() {
	release();
}

Dictionary WindowsArchiveLease::try_acquire(const String &p_profiles_directory, const String &p_profile_id) {
	if (lock_file_ != INVALID_HANDLE_VALUE) {
		last_error_ = "lease_already_acquired";
		return make_result(false, last_error_);
	}
	if (!p_profile_id.is_empty() && !is_profile_id(p_profile_id)) {
		last_error_ = "invalid_profile_id";
		return make_result(false, last_error_);
	}

	std::wstring identity;
	if (!get_directory_identity(p_profiles_directory, identity, last_error_)) {
		return make_result(false, last_error_);
	}

	std::wstring lock_path = identity;
	lock_path.append(L"\\");
	lock_path.append(p_profile_id.is_empty() ? L".directory.lock" : to_wide_string(p_profile_id) + L".lock");

	HANDLE lock_file = CreateFileW(
			lock_path.c_str(),
			GENERIC_READ | GENERIC_WRITE,
			FILE_SHARE_READ | FILE_SHARE_WRITE,
			nullptr,
			OPEN_ALWAYS,
			FILE_ATTRIBUTE_HIDDEN | FILE_FLAG_OPEN_REPARSE_POINT,
			nullptr);
	if (lock_file == INVALID_HANDLE_VALUE) {
		last_error_ = "lock_file_open_failed:" + String::num_int64(GetLastError());
		return make_result(false, last_error_);
	}

	BY_HANDLE_FILE_INFORMATION information = {};
	if (GetFileInformationByHandle(lock_file, &information) == 0) {
		last_error_ = "lock_file_info_failed:" + String::num_int64(GetLastError());
		CloseHandle(lock_file);
		return make_result(false, last_error_);
	}
	if ((information.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0) {
		last_error_ = "lock_file_type_mismatch";
		CloseHandle(lock_file);
		return make_result(false, last_error_);
	}

	OVERLAPPED lock_range = {};
	if (LockFileEx(
				lock_file,
				LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY,
				0,
				1,
				0,
				&lock_range) == 0) {
		const DWORD error_code = GetLastError();
		last_error_ = error_code == ERROR_LOCK_VIOLATION ? "profile_in_use" :
														 "profile_lock_failed:" + String::num_int64(error_code);
		CloseHandle(lock_file);
		return make_result(false, last_error_);
	}

	lock_file_ = lock_file;
	lock_range_ = lock_range;
	directory_identity_ = identity;
	profile_id_ = p_profile_id;
	last_error_ = String();
	return make_result(true);
}

Dictionary WindowsArchiveLease::enumerate_profile_candidates(const String &p_profiles_directory) const {
	if (!profile_id_.is_empty()) {
		return make_result(false, "directory_lease_required");
	}
	String error;
	if (!directory_matches_lease(p_profiles_directory, error)) {
		return make_result(false, error);
	}

	const std::wstring search_path = directory_identity_ + L"\\*";
	WIN32_FIND_DATAW find_data = {};
	HANDLE search_handle = FindFirstFileW(search_path.c_str(), &find_data);
	if (search_handle == INVALID_HANDLE_VALUE) {
		const DWORD error_code = GetLastError();
		if (error_code == ERROR_FILE_NOT_FOUND) {
			Dictionary result = make_result(true);
			result["entries"] = Array();
			return result;
		}
		return make_result(false, "directory_enumeration_failed:" + String::num_int64(error_code));
	}

	Array entries;
	do {
		const std::wstring file_name(find_data.cFileName);
		if (file_name == L"." || file_name == L".." || !is_json_candidate(file_name)) {
			continue;
		}
		Dictionary entry;
		entry["name"] = from_wide_string(file_name);
		entry["is_directory"] = (find_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
		entry["is_reparse_point"] = (find_data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
		entries.push_back(entry);
	} while (FindNextFileW(search_handle, &find_data) != 0);

	const DWORD enumeration_error = GetLastError();
	FindClose(search_handle);
	if (enumeration_error != ERROR_NO_MORE_FILES) {
		return make_result(false, "directory_enumeration_failed:" + String::num_int64(enumeration_error));
	}

	Dictionary result = make_result(true);
	result["entries"] = entries;
	return result;
}

Dictionary WindowsArchiveLease::read_profile_candidate(
		const String &p_profiles_directory,
		const String &p_file_name) const {
	if (!profile_id_.is_empty()) {
		return make_result(false, "directory_lease_required");
	}
	if (!is_candidate_name(p_file_name)) {
		return make_result(false, "invalid_file_name");
	}

	String error;
	if (!directory_matches_lease(p_profiles_directory, error)) {
		return make_result(false, error);
	}

	const std::wstring file_path = directory_identity_ + L"\\" + to_wide_string(p_file_name);
	HANDLE candidate = CreateFileW(
			file_path.c_str(),
			GENERIC_READ,
			FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
			nullptr,
			OPEN_EXISTING,
			FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_SEQUENTIAL_SCAN,
			nullptr);
	if (candidate == INVALID_HANDLE_VALUE) {
		const DWORD error_code = GetLastError();
		return make_result(false, "candidate_open_failed:" + String::num_int64(error_code));
	}

	BY_HANDLE_FILE_INFORMATION information = {};
	if (GetFileInformationByHandle(candidate, &information) == 0) {
		const DWORD error_code = GetLastError();
		CloseHandle(candidate);
		return make_result(false, "candidate_info_failed:" + String::num_int64(error_code));
	}
	if ((information.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0) {
		CloseHandle(candidate);
		return make_result(false, "candidate_type_mismatch");
	}

	LARGE_INTEGER file_size = {};
	if (GetFileSizeEx(candidate, &file_size) == 0 || file_size.QuadPart < 0) {
		const DWORD error_code = GetLastError();
		CloseHandle(candidate);
		return make_result(false, "candidate_size_failed:" + String::num_int64(error_code));
	}

	PackedByteArray contents;
	contents.resize(file_size.QuadPart);
	int64_t total_read = 0;
	while (total_read < file_size.QuadPart) {
		const DWORD requested = static_cast<DWORD>(std::min<int64_t>(
				file_size.QuadPart - total_read,
				std::numeric_limits<DWORD>::max()));
		DWORD bytes_read = 0;
		if (ReadFile(candidate, contents.ptrw() + total_read, requested, &bytes_read, nullptr) == 0 ||
				bytes_read != requested) {
			const DWORD error_code = GetLastError();
			CloseHandle(candidate);
			return make_result(false, "candidate_read_failed:" + String::num_int64(error_code));
		}
		total_read += bytes_read;
	}
	CloseHandle(candidate);

	Dictionary result = make_result(true);
	result["bytes"] = contents;
	return result;
}

Dictionary WindowsArchiveLease::normalize_profile_name(const String &p_profile_name) const {
	if (has_forbidden_name_codepoint(p_profile_name)) {
		return make_result(false, "profile_name_contains_control");
	}

	const String trimmed = p_profile_name.strip_edges();
	if (trimmed.is_empty()) {
		return make_result(false, "profile_name_length");
	}

	std::wstring normalized;
	if (!normalize_windows_text(to_wide_string(trimmed), normalized)) {
		return make_result(false, "profile_name_normalization_failed");
	}

	const String display_name = from_wide_string(normalized);
	if (display_name.length() < 2 || display_name.length() > 16 ||
			has_forbidden_name_codepoint(display_name) ||
			display_name != display_name.strip_edges()) {
		return make_result(false, "profile_name_invalid");
	}

	const int folded_length = LCMapStringEx(
			LOCALE_NAME_INVARIANT,
			LCMAP_LOWERCASE | LCMAP_LINGUISTIC_CASING,
			normalized.c_str(),
			static_cast<int>(normalized.size()),
			nullptr,
			0,
			nullptr,
			nullptr,
			0);
	if (folded_length <= 0) {
		return make_result(false, "profile_name_comparison_failed");
	}
	std::vector<wchar_t> folded_buffer(static_cast<size_t>(folded_length));
	const int folded_written = LCMapStringEx(
			LOCALE_NAME_INVARIANT,
			LCMAP_LOWERCASE | LCMAP_LINGUISTIC_CASING,
			normalized.c_str(),
			static_cast<int>(normalized.size()),
			folded_buffer.data(),
			folded_length,
			nullptr,
			nullptr,
			0);
	if (folded_written <= 0 || folded_written > folded_length) {
		return make_result(false, "profile_name_comparison_failed");
	}

	std::wstring comparison_key;
	if (!normalize_windows_text(
				std::wstring(folded_buffer.data(), static_cast<size_t>(folded_written)),
				comparison_key)) {
		return make_result(false, "profile_name_comparison_failed");
	}

	Dictionary result = make_result(true);
	result["profile_name"] = display_name;
	result["comparison_key"] = from_wide_string(comparison_key);
	return result;
}

Dictionary WindowsArchiveLease::publish_bytes(
		const String &p_profiles_directory,
		const String &p_temporary_name,
		const String &p_target_name,
		const PackedByteArray &p_contents,
		bool p_replace) {
	if (!is_leaf_name(p_temporary_name) || !is_leaf_name(p_target_name)) {
		last_error_ = "invalid_file_name";
		return make_result(false, last_error_);
	}

	String error;
	if (!directory_matches_lease(p_profiles_directory, error)) {
		last_error_ = error;
		return make_result(false, last_error_);
	}

	const std::wstring temporary_path = directory_identity_ + L"\\" + to_wide_string(p_temporary_name);
	const std::wstring target_path = directory_identity_ + L"\\" + to_wide_string(p_target_name);
	if (!validate_publish_target(target_path, p_replace, error)) {
		last_error_ = error;
		return make_result(false, last_error_);
	}

	HANDLE temporary_file = CreateFileW(
			temporary_path.c_str(),
			GENERIC_WRITE,
			0,
			nullptr,
			CREATE_NEW,
			FILE_ATTRIBUTE_HIDDEN | FILE_FLAG_WRITE_THROUGH | FILE_FLAG_OPEN_REPARSE_POINT,
			nullptr);
	if (temporary_file == INVALID_HANDLE_VALUE) {
		last_error_ = "temporary_file_create_failed:" + String::num_int64(GetLastError());
		return make_result(false, last_error_);
	}

	const int64_t content_length = p_contents.size();
	int64_t written = 0;
	while (written < content_length) {
		const DWORD chunk_length = static_cast<DWORD>(std::min<int64_t>(
				content_length - written,
				std::numeric_limits<DWORD>::max()));
		DWORD chunk_written = 0;
		if (WriteFile(
					temporary_file,
					p_contents.ptr() + written,
					chunk_length,
					&chunk_written,
					nullptr) == 0 ||
				chunk_written != chunk_length) {
			const DWORD error_code = GetLastError();
			CloseHandle(temporary_file);
			DeleteFileW(temporary_path.c_str());
			last_error_ = "temporary_file_write_failed:" + String::num_int64(error_code);
			return make_result(false, last_error_);
		}
		written += chunk_written;
	}

	if (FlushFileBuffers(temporary_file) == 0) {
		const DWORD error_code = GetLastError();
		CloseHandle(temporary_file);
		DeleteFileW(temporary_path.c_str());
		last_error_ = "temporary_file_flush_failed:" + String::num_int64(error_code);
		return make_result(false, last_error_);
	}
	CloseHandle(temporary_file);

	DWORD move_flags = MOVEFILE_WRITE_THROUGH;
	if (p_replace) {
		move_flags |= MOVEFILE_REPLACE_EXISTING;
	}
	if (MoveFileExW(temporary_path.c_str(), target_path.c_str(), move_flags) == 0) {
		const DWORD error_code = GetLastError();
		DeleteFileW(temporary_path.c_str());
		last_error_ = "atomic_publish_failed:" + String::num_int64(error_code);
		return make_result(false, last_error_);
	}

	last_error_ = String();
	return make_result(true);
}

void WindowsArchiveLease::release() {
	if (lock_file_ == INVALID_HANDLE_VALUE) {
		return;
	}
	UnlockFileEx(lock_file_, 0, 1, 0, &lock_range_);
	CloseHandle(lock_file_);
	lock_file_ = INVALID_HANDLE_VALUE;
	lock_range_ = {};
	directory_identity_.clear();
	profile_id_ = String();
}

bool WindowsArchiveLease::is_acquired() const {
	return lock_file_ != INVALID_HANDLE_VALUE;
}

String WindowsArchiveLease::get_last_error() const {
	return last_error_;
}

} // namespace godot
