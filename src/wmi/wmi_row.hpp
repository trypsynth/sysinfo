#pragma once
#include <string>
#include <vector>
#include <wbemidl.h>

// Move-only wrapper around a single WMI result object.
class wmi_row {
public:
	explicit wmi_row(IWbemClassObject* obj);
	~wmi_row();
	wmi_row(const wmi_row&) = delete;
	wmi_row& operator=(const wmi_row&) = delete;
	wmi_row(wmi_row&& other) noexcept;
	wmi_row& operator=(wmi_row&& other) noexcept;
	// Returns the property formatted as text, or "" if missing/null.
	std::wstring get(const wchar_t* property) const;
	// Returns a multi-valued (array) property as separate elements, e.g. the several addresses in IPAddress. Empty if missing or not an array.
	std::vector<std::wstring> get_list(const wchar_t* property) const;
private:
	IWbemClassObject* obj_;
};
