#include "format.hpp"
#include <cwchar>
#include <exception>
#include <vector>

namespace {
std::wstring pluralize(unsigned long long count, const wchar_t* singular) {
	return std::to_wstring(count) + L" " + singular + (count == 1 ? L"" : L"s");
}

std::wstring join_with_and(const std::vector<std::wstring>& parts) {
	if (parts.size() == 1) return parts[0];
	if (parts.size() == 2) return parts[0] + L" and " + parts[1];
	std::wstring result;
	for (size_t i = 0; i < parts.size(); ++i) {
		if (i > 0) result += (i + 1 == parts.size()) ? L", and " : L", ";
		result += parts[i];
	}
	return result;
}
}  // namespace

std::wstring format_bytes(const std::wstring& bytes_str) {
	if (bytes_str.empty()) return bytes_str;
	try {
		unsigned long long bytes = std::stoull(bytes_str);
		static const wchar_t* units[] = {L"B", L"KB", L"MB", L"GB", L"TB", L"PB"};
		double value = static_cast<double>(bytes);
		size_t unit_index = 0;
		while (value >= 1024.0 && unit_index < 5) {
			value /= 1024.0;
			++unit_index;
		}
		wchar_t buf[64];
		swprintf(buf, 64, L"%.1f %ls", value, units[unit_index]);
		return buf;
	} catch (const std::exception&) {
		return bytes_str;
	}
}

std::wstring with_unit(const std::wstring& value, const std::wstring& suffix) {
	return value.empty() ? value : value + suffix;
}

std::wstring format_percent(double part, double whole) {
	if (whole <= 0.0) return L"";
	wchar_t buf[16];
	swprintf(buf, 16, L"%.1f%%", (part / whole) * 100.0);
	return buf;
}

std::wstring format_duration(unsigned long long total_seconds) {
	unsigned long long days = total_seconds / 86400;
	unsigned long long hours = (total_seconds % 86400) / 3600;
	unsigned long long minutes = (total_seconds % 3600) / 60;
	unsigned long long seconds = total_seconds % 60;
	std::vector<std::wstring> parts;
	if (days > 0) parts.push_back(pluralize(days, L"day"));
	if (hours > 0) parts.push_back(pluralize(hours, L"hour"));
	if (minutes > 0) parts.push_back(pluralize(minutes, L"minute"));
	if (seconds > 0 || parts.empty()) parts.push_back(pluralize(seconds, L"second"));
	return join_with_and(parts);
}
