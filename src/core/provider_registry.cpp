#include "provider_registry.hpp"

provider_registry& provider_registry::instance() {
	static provider_registry inst;
	return inst;
}

void provider_registry::register_provider(factory f) { factories_.push_back(std::move(f)); }

std::vector<std::unique_ptr<category_provider>> provider_registry::create_all() const {
	std::vector<std::unique_ptr<category_provider>> providers;
	providers.reserve(factories_.size());
	for (const auto& f : factories_) providers.push_back(f());
	return providers;
}
