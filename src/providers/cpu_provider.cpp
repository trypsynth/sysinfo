#include "core/category_provider.hpp"
#include "core/format.hpp"
#include "core/provider_registry.hpp"
#include "wmi/wmi_connection.hpp"

namespace {
std::wstring decode_bool(const std::wstring& raw) {
	if (raw.empty()) return L"";
	return raw == L"True" ? L"Yes" : L"No";
}
}  // namespace

class cpu_provider : public category_provider {
public:
	std::vector<category_item> get_items() override {
		auto rows = wmi_connection::instance().query(L"SELECT Name, Manufacturer, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, L2CacheSize, L3CacheSize, SocketDesignation, VirtualizationFirmwareEnabled FROM Win32_Processor");
		std::vector<category_item> items;
		for (const auto& row : rows) {
			category_item item;
			std::wstring name = row.get(L"Name");
			item.label = rows.size() > 1 ? (L"Processor, " + name) : L"Processor";
			item.properties = {{L"Name", name}, {L"Manufacturer", row.get(L"Manufacturer")}, {L"Socket", row.get(L"SocketDesignation")}, {L"Cores", row.get(L"NumberOfCores")}, {L"Logical Processors", row.get(L"NumberOfLogicalProcessors")}, {L"Max Clock Speed", with_unit(row.get(L"MaxClockSpeed"), L" MHz")}, {L"L2 Cache", with_unit(row.get(L"L2CacheSize"), L" KB")}, {L"L3 Cache", with_unit(row.get(L"L3CacheSize"), L" KB")}, {L"Virtualization Enabled", decode_bool(row.get(L"VirtualizationFirmwareEnabled"))}};
			items.push_back(std::move(item));
		}
		return items;
	}
};
REGISTER_PROVIDER(cpu_provider)
