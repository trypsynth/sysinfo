#include "core/category_provider.hpp"
#include "core/provider_registry.hpp"
#include "wmi/wmi_connection.hpp"
#include "wmi/wmi_date_time.hpp"
#include <windows.h>

namespace {
std::wstring bios_mode() {
	FIRMWARE_TYPE firmware_type = FirmwareTypeUnknown;
	if (!GetFirmwareType(&firmware_type)) return L"";
	if (firmware_type == FirmwareTypeUefi) return L"UEFI";
	if (firmware_type == FirmwareTypeBios) return L"Legacy";
	return L"";
}

// Only meaningful under UEFI; the key simply doesn't exist on Legacy BIOS systems, which we treat the same as "can't determine" and leave blank.
std::wstring secure_boot_status() {
	DWORD value = 0;
	DWORD size = sizeof(value);
	if (RegGetValueW(HKEY_LOCAL_MACHINE, L"SYSTEM\\CurrentControlSet\\Control\\SecureBoot\\State", L"UEFISecureBootEnabled", RRF_RT_REG_DWORD, nullptr, &value, &size) != ERROR_SUCCESS) return L"";
	return value ? L"Enabled" : L"Disabled";
}
}  // namespace

class bios_provider : public category_provider {
public:
	std::vector<category_item> get_items() override {
		auto rows = wmi_connection::instance().query(L"SELECT Manufacturer, SMBIOSBIOSVersion, ReleaseDate, SerialNumber FROM Win32_BIOS");
		std::vector<category_item> items;
		if (rows.empty()) return items;
		const auto& row = rows.front();
		category_item item;
		item.label = L"BIOS";
		item.properties = {{L"Manufacturer", row.get(L"Manufacturer")}, {L"Version", row.get(L"SMBIOSBIOSVersion")}, {L"Release Date", format_wmi_date_time(row.get(L"ReleaseDate"))}, {L"Mode", bios_mode()}, {L"Secure Boot", secure_boot_status()}, {L"Serial Number", row.get(L"SerialNumber")}};
		items.push_back(std::move(item));
		return items;
	}
};
REGISTER_PROVIDER(bios_provider)
