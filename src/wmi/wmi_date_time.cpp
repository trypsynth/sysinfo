#include "wmi_date_time.hpp"

std::wstring format_wmi_date_time(const std::wstring& raw) {
	if (raw.size() < 14) return raw;
	return raw.substr(0, 4) + L"-" + raw.substr(4, 2) + L"-" + raw.substr(6, 2) + L" " + raw.substr(8, 2) + L":" + raw.substr(10, 2) + L":" + raw.substr(12, 2);
}
