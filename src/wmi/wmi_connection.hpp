#pragma once
#include <string>
#include <unordered_map>
#include <vector>
#include <wbemidl.h>
#include "wmi_row.hpp"

// Lazily-initialized, process-wide WMI connection. Providers never touch COM/WBEM directly - they just call query() with a WQL string, optionally against a specific namespace (most WMI classes live in ROOT\CIMV2, the default; some newer ones like MSFT_NetIPAddress live in ROOT\StandardCimv2).
class wmi_connection {
public:
	static wmi_connection& instance();
	// Throws std::runtime_error on failure.
	std::vector<wmi_row> query(const std::wstring& wql, const std::wstring& wmi_namespace = L"ROOT\\CIMV2");
	wmi_connection(const wmi_connection&) = delete;
	wmi_connection& operator=(const wmi_connection&) = delete;
private:
	wmi_connection();
	~wmi_connection();
	IWbemServices* connect(const std::wstring& wmi_namespace);
	bool com_initialized_ = false;
	IWbemLocator* locator_ = nullptr;
	std::unordered_map<std::wstring, IWbemServices*> services_by_namespace_;
};
