#pragma once
#include <string>

// Converts a raw CIM_DATETIME string (e.g. "20250110083000.000000-480") into "YYYY-MM-DD HH:MM:SS". Returns the input unchanged if it doesn't look like a CIM datetime, since that's more useful to read than nothing.
std::wstring format_wmi_date_time(const std::wstring& raw);
