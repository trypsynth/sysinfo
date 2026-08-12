#pragma once
#include <vector>
#include "category_item.hpp"

// One provider corresponds to one hardware/software domain (CPU, storage, ...). get_items() can return more than one category_item when the domain has multiple instances (e.g. one item per disk, one per network adapter).
class category_provider {
public:
	virtual ~category_provider() = default;
	virtual std::vector<category_item> get_items() = 0;
};
