#pragma once
#include <functional>
#include <memory>
#include <vector>
#include "category_provider.hpp"

// Self-registering provider registry. Each provider .cpp registers itself via REGISTER_PROVIDER at static-init time, so adding a new category never requires editing this file or any list of categories elsewhere.
class provider_registry {
public:
	using factory = std::function<std::unique_ptr<category_provider>()>;
	static provider_registry& instance();
	void register_provider(factory f);
	std::vector<std::unique_ptr<category_provider>> create_all() const;
private:
	provider_registry() = default;
	std::vector<factory> factories_;
};

template <typename T>
struct provider_registrar {
	provider_registrar() { provider_registry::instance().register_provider([] { return std::make_unique<T>(); }); }
};

// Placed at namespace scope in a provider .cpp file. Expands to a static object whose constructor registers T with the registry before main() runs.
#define REGISTER_PROVIDER(T) static provider_registrar<T> g_registrar_##T;
