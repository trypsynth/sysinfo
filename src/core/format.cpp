#include "format.hpp"
#include <cwchar>
#include <exception>

std::wstring format_bytes_as_gb(const std::wstring& bytes_str) {
	if (bytes_str.empty()) return bytes_str;
	try {
		unsigned long long bytes = std::stoull(bytes_str);
		double gb = static_cast<double>(bytes) / (1024.0 * 1024.0 * 1024.0);
		wchar_t buf[64];
		swprintf(buf, 64, L"%.1f GB", gb);
		return buf;
	} catch (const std::exception&) {
		return bytes_str;
	}
}

std::wstring with_unit(const std::wstring& value, const std::wstring& suffix) {
	return value.empty() ? value : value + suffix;
}
