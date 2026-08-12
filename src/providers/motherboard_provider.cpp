#include "core/category_provider.hpp"
#include "core/provider_registry.hpp"
#include "wmi/wmi_connection.hpp"

class motherboard_provider : public category_provider {
public:
	std::vector<category_item> get_items() override {
		auto rows = wmi_connection::instance().query(L"SELECT Manufacturer, Product, Version, SerialNumber FROM Win32_BaseBoard");
		std::vector<category_item> items;
		if (rows.empty()) return items;
		const auto& row = rows.front();
		category_item item;
		item.label = L"Motherboard";
		item.properties = {{L"Manufacturer", row.get(L"Manufacturer")}, {L"Product", row.get(L"Product")}, {L"Version", row.get(L"Version")}, {L"Serial Number", row.get(L"SerialNumber")}};
		items.push_back(std::move(item));
		return items;
	}
};
REGISTER_PROVIDER(motherboard_provider)
