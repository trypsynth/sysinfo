#include "core/category_provider.hpp"
#include "core/provider_registry.hpp"
#include "wmi/wmi_connection.hpp"
#include <cwchar>
#include <exception>
#include <unordered_set>

namespace {
// Link-local unicast addresses are defined by the fe80::/10 prefix (RFC 4291) - this is a purely syntactic check, not a WMI-provided flag.
bool is_link_local_ipv6(const std::wstring& address) { return _wcsnicmp(address.c_str(), L"fe80:", 5) == 0; }

// SuffixOrigin = 5 (Random) marks an RFC 4941 privacy address - the same flag ipconfig uses to label "Temporary IPv6 Address". That flag only exists on the newer MSFT_NetIPAddress class (ROOT\StandardCimv2), not Win32_NetworkAdapterConfiguration, hence the separate query. Falls back to an empty set if that class isn't available (pre-Windows 8).
std::unordered_set<std::wstring> temporary_ipv6_addresses() {
	std::unordered_set<std::wstring> result;
	try {
		for (const auto& row : wmi_connection::instance().query(L"SELECT IPAddress FROM MSFT_NetIPAddress WHERE AddressFamily = 23 AND SuffixOrigin = 5", L"ROOT\\StandardCimv2")) result.insert(row.get(L"IPAddress"));
	} catch (const std::exception&) {
	}
	return result;
}
}  // namespace

class network_provider : public category_provider {
public:
	std::vector<category_item> get_items() override {
		auto temp_addresses = temporary_ipv6_addresses();
		auto rows = wmi_connection::instance().query(L"SELECT Description, MACAddress, IPAddress, IPSubnet, DefaultIPGateway, DNSServerSearchOrder, DNSDomain, DHCPEnabled FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled = TRUE");
		std::vector<category_item> items;
		for (const auto& row : rows) {
			category_item item;
			item.label = L"Network, " + row.get(L"Description");
			item.properties = {{L"MAC Address", row.get(L"MACAddress")}};
			std::vector<std::wstring> ipv4, ipv6, ipv6_temporary, ipv6_link_local;
			for (const auto& address : row.get_list(L"IPAddress")) {
				if (address.find(L':') == std::wstring::npos) ipv4.push_back(address);
				else if (is_link_local_ipv6(address)) ipv6_link_local.push_back(address);
				else if (temp_addresses.count(address)) ipv6_temporary.push_back(address);
				else ipv6.push_back(address);
			}
			for (size_t i = 0; i < ipv4.size(); ++i) item.properties.push_back({ipv4.size() > 1 ? L"IPv4 Address " + std::to_wstring(i + 1) : L"IPv4 Address", ipv4[i]});
			for (size_t i = 0; i < ipv6.size(); ++i) item.properties.push_back({ipv6.size() > 1 ? L"IPv6 Address " + std::to_wstring(i + 1) : L"IPv6 Address", ipv6[i]});
			for (size_t i = 0; i < ipv6_temporary.size(); ++i) item.properties.push_back({ipv6_temporary.size() > 1 ? L"Temporary IPv6 Address " + std::to_wstring(i + 1) : L"Temporary IPv6 Address", ipv6_temporary[i]});
			for (size_t i = 0; i < ipv6_link_local.size(); ++i) item.properties.push_back({ipv6_link_local.size() > 1 ? L"Link-local IPv6 Address " + std::to_wstring(i + 1) : L"Link-local IPv6 Address", ipv6_link_local[i]});
			item.properties.push_back({L"Subnet Mask", row.get(L"IPSubnet")});
			item.properties.push_back({L"Default Gateway", row.get(L"DefaultIPGateway")});
			item.properties.push_back({L"DNS Servers", row.get(L"DNSServerSearchOrder")});
			item.properties.push_back({L"DNS Suffix", row.get(L"DNSDomain")});
			item.properties.push_back({L"DHCP Enabled", row.get(L"DHCPEnabled")});
			items.push_back(std::move(item));
		}
		return items;
	}
};
REGISTER_PROVIDER(network_provider)
