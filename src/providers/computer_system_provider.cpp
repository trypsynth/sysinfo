#include "core/category_provider.hpp"
#include "core/provider_registry.hpp"
#include "wmi/wmi_connection.hpp"

namespace {
// PCSystemType says what kind of machine this is. 0 (Unspecified) and anything unmapped falls through to "", which the existing blank property filtering drops.
std::wstring decode_system_type(const std::wstring& raw) {
	if (raw == L"1") return L"Desktop";
	if (raw == L"2") return L"Laptop";
	if (raw == L"3") return L"Workstation";
	if (raw == L"4") return L"Enterprise Server";
	if (raw == L"5") return L"Small Office Server";
	if (raw == L"6") return L"Appliance PC";
	if (raw == L"7") return L"Performance Server";
	if (raw == L"8") return L"Maximum";
	return L"";
}
}  // namespace

class computer_system_provider : public category_provider {
public:
	std::vector<category_item> get_items() override {
		auto rows = wmi_connection::instance().query(L"SELECT Manufacturer, Model, SystemType, PCSystemType, Domain, PartOfDomain FROM Win32_ComputerSystem");
		std::vector<category_item> items;
		if (rows.empty()) return items;
		const auto& row = rows.front();
		category_item item;
		item.label = L"Computer System";
		item.properties = {{L"Manufacturer", row.get(L"Manufacturer")}, {L"Model", row.get(L"Model")}, {L"Type", decode_system_type(row.get(L"PCSystemType"))}, {L"Architecture", row.get(L"SystemType")}};
		bool part_of_domain = row.get(L"PartOfDomain") == L"True";
		item.properties.push_back({part_of_domain ? L"Domain" : L"Workgroup", row.get(L"Domain")});
		items.push_back(std::move(item));
		return items;
	}
};
REGISTER_PROVIDER(computer_system_provider)
