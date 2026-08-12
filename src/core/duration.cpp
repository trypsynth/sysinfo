#include "duration.hpp"
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
