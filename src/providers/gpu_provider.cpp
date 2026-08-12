#include "core/category_provider.hpp"
#include "core/format.hpp"
#include "core/provider_registry.hpp"
#include "wmi/wmi_connection.hpp"

class gpu_provider : public category_provider {
public:
	std::vector<category_item> get_items() override {
		auto rows = wmi_connection::instance().query(L"SELECT Name, AdapterCompatibility, DriverVersion, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate, AdapterRAM FROM Win32_VideoController");
		std::vector<category_item> items;
		for (const auto& row : rows) {
			category_item item;
			item.label = L"GPU, " + row.get(L"Name");
			item.properties = {{L"Vendor", row.get(L"AdapterCompatibility")}, {L"Driver Version", row.get(L"DriverVersion")}, {L"Refresh Rate", with_unit(row.get(L"CurrentRefreshRate"), L" Hz")}, {L"Video Memory", format_bytes_as_gb(row.get(L"AdapterRAM"))}};
			std::wstring width = row.get(L"CurrentHorizontalResolution");
			std::wstring height = row.get(L"CurrentVerticalResolution");
			if (!width.empty() && !height.empty()) item.properties.push_back({L"Current Resolution", width + L" x " + height});
			items.push_back(std::move(item));
		}
		return items;
	}
};
REGISTER_PROVIDER(gpu_provider)
