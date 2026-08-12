#include "core/category_provider.hpp"
#include "core/format.hpp"
#include "core/provider_registry.hpp"
#include "wmi/wmi_connection.hpp"
#include <exception>
#include <windows.h>

namespace {
std::wstring format_kb_as_gb(unsigned long long kb) { return format_bytes(std::to_wstring(kb * 1024ULL)); }

// SMBIOSMemoryType is a raw SMBIOS Memory Device Type byte; Microsoft's own docs only officially list values up to 26 (DDR4), but real hardware reports the newer SMBIOS-spec values for DDR5 and beyond too. 0 (Unknown) and anything not confidently mapped falls through to "", which the existing blank-property filtering drops.
std::wstring decode_memory_type(const std::wstring& raw) {
	if (raw == L"17") return L"SDRAM";
	if (raw == L"19") return L"RDRAM";
	if (raw == L"20") return L"DDR";
	if (raw == L"21") return L"DDR2";
	if (raw == L"22") return L"DDR2 FB-DIMM";
	if (raw == L"24") return L"DDR3";
	if (raw == L"25") return L"FBD2";
	if (raw == L"26") return L"DDR4";
	if (raw == L"27") return L"LPDDR";
	if (raw == L"28") return L"LPDDR2";
	if (raw == L"29") return L"LPDDR3";
	if (raw == L"30") return L"LPDDR4";
	if (raw == L"32") return L"HBM";
	if (raw == L"33") return L"HBM2";
	if (raw == L"34") return L"DDR5";
	if (raw == L"35") return L"LPDDR5";
	return L"";
}

std::wstring decode_form_factor(const std::wstring& raw) {
	if (raw == L"7") return L"SIMM";
	if (raw == L"8") return L"DIMM";
	if (raw == L"11") return L"RIMM";
	if (raw == L"12") return L"SODIMM";
	if (raw == L"13") return L"SRIMM";
	return L"";
}
}  // namespace

class memory_provider : public category_provider {
public:
	std::vector<category_item> get_items() override {
		std::vector<category_item> items;
		category_item summary;
		summary.label = L"Memory, Summary";

		// GetPhysicallyInstalledSystemMemory reads the true SMBIOS-reported total; Win32_ComputerSystem.TotalPhysicalMemory can be slightly off since it reflects what the OS sees after some early-boot exclusions.
		ULONGLONG installed_kb = 0;
		bool have_installed = GetPhysicallyInstalledSystemMemory(&installed_kb) != FALSE;
		if (have_installed) summary.properties.push_back({L"Physically Installed", format_kb_as_gb(installed_kb)});

		auto os_rows = wmi_connection::instance().query(L"SELECT TotalVisibleMemorySize, FreePhysicalMemory FROM Win32_OperatingSystem");
		if (!os_rows.empty()) {
			try {
				unsigned long long visible_kb = std::stoull(os_rows.front().get(L"TotalVisibleMemorySize"));
				summary.properties.push_back({L"Available to Windows", format_kb_as_gb(visible_kb)});
				// The gap between what's physically installed and what Windows can actually use is memory the firmware carved out before the OS ever saw it - this is the same figure Task Manager labels "Hardware reserved" (can include things like an integrated GPU's dedicated framebuffer, but WMI has no reliable way to attribute how much of it is GPU-specific).
				if (have_installed && installed_kb > visible_kb) summary.properties.push_back({L"Hardware Reserved", format_kb_as_gb(installed_kb - visible_kb)});
			} catch (const std::exception&) {
			}
			try {
				summary.properties.push_back({L"Free", format_kb_as_gb(std::stoull(os_rows.front().get(L"FreePhysicalMemory")))});
			} catch (const std::exception&) {
			}
		}

		items.push_back(std::move(summary));

		auto module_rows = wmi_connection::instance().query(L"SELECT DeviceLocator, BankLabel, Capacity, Speed, Manufacturer, SMBIOSMemoryType, FormFactor FROM Win32_PhysicalMemory");
		for (const auto& row : module_rows) {
			category_item item;
			std::wstring locator = row.get(L"DeviceLocator");
			item.label = L"Memory, " + (locator.empty() ? L"Module" : locator);
			item.properties = {{L"Bank", row.get(L"BankLabel")}, {L"Type", decode_memory_type(row.get(L"SMBIOSMemoryType"))}, {L"Form Factor", decode_form_factor(row.get(L"FormFactor"))}, {L"Capacity", format_bytes(row.get(L"Capacity"))}, {L"Speed", with_unit(row.get(L"Speed"), L" MHz")}, {L"Manufacturer", row.get(L"Manufacturer")}};
			items.push_back(std::move(item));
		}
		return items;
	}
};
REGISTER_PROVIDER(memory_provider)
