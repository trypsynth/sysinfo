#pragma once
#include <string>
#include <vector>

struct property_row {
	std::wstring name;
	std::wstring value;
};

struct category_item {
	std::wstring label;
	std::vector<property_row> properties;
};
