#include "core/category_provider.hpp"
#include "core/format.hpp"
#include "core/provider_registry.hpp"
#include "wmi/wmi_connection.hpp"
#include "wmi/wmi_date_time.hpp"
#include <windows.h>

class os_provider : public category_provider {
public:
	std::vector<category_item> get_items() override {
		auto rows = wmi_connection::instance().query(L"SELECT Caption, Version, BuildNumber, OSArchitecture, InstallDate, LastBootUpTime, SerialNumber, RegisteredUser, CSName, WindowsDirectory, SystemDirectory, SystemDrive, NumberOfProcesses, NumberOfUsers FROM Win32_OperatingSystem");
		std::vector<category_item> items;
		if (rows.empty()) return items;
		const auto& row = rows.front();
		category_item item;
		item.label = L"Operating System";
		item.properties = {{L"Name", row.get(L"Caption")}, {L"Computer Name", row.get(L"CSName")}, {L"Version", row.get(L"Version")}, {L"Build Number", row.get(L"BuildNumber")}, {L"Architecture", row.get(L"OSArchitecture")}, {L"Install Date", format_wmi_date_time(row.get(L"InstallDate"))}, {L"Last Boot", format_wmi_date_time(row.get(L"LastBootUpTime"))}, {L"Uptime", format_duration(GetTickCount64() / 1000)}, {L"Registered User", row.get(L"RegisteredUser")}, {L"Serial Number", row.get(L"SerialNumber")}, {L"Windows Directory", row.get(L"WindowsDirectory")}, {L"System Directory", row.get(L"SystemDirectory")}, {L"System Drive", row.get(L"SystemDrive")}, {L"Running Processes", row.get(L"NumberOfProcesses")}, {L"Logged-on Users", row.get(L"NumberOfUsers")}};
		items.push_back(std::move(item));
		return items;
	}
};
REGISTER_PROVIDER(os_provider)
