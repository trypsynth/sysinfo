#include "core/category_provider.hpp"
#include "core/duration.hpp"
#include "core/format.hpp"
#include "core/provider_registry.hpp"
#include "wmi/wmi_connection.hpp"
#include <cwchar>
#include <exception>

namespace {
std::wstring decode_chemistry(const std::wstring& raw) {
	if (raw == L"1") return L"Other";
	if (raw == L"2") return L"Unknown";
	if (raw == L"3") return L"Lead Acid";
	if (raw == L"4") return L"Nickel Cadmium";
	if (raw == L"5") return L"Nickel Metal Hydride";
	if (raw == L"6") return L"Lithium-ion";
	if (raw == L"7") return L"Zinc Air";
	if (raw == L"8") return L"Lithium Polymer";
	return raw;
}

// Win32_Battery's own BatteryStatus enum is unreliable on modern hardware, confirmed reporting 2 (Unknown) while plugged in and 1 (Other) while unplugged, neither of which reflects reality. ROOT\WMI's BatteryStatus class (same name, unrelated class, the ACPI battery driver's live status block) gives the real Charging/Discharging/PowerOnline booleans instead, the same fix already applied to capacity below. Plugged in with neither flag set usually means fully charged, but not always, some laptops cap charging below 100 percent for battery health, so that case is cross checked against the actual charge percentage rather than assumed.
std::wstring live_status(const std::wstring& charge_remaining) {
	try {
		auto rows = wmi_connection::instance().query(L"SELECT Charging, Discharging, PowerOnline, Critical FROM BatteryStatus", L"ROOT\\WMI");
		if (rows.empty()) return L"";
		const auto& row = rows.front();
		if (row.get(L"Critical") == L"True") return L"Critical";
		if (row.get(L"Charging") == L"True") return L"Charging";
		if (row.get(L"Discharging") == L"True") return L"Discharging";
		if (row.get(L"PowerOnline") == L"True") {
			try {
				if (!charge_remaining.empty() && std::stod(charge_remaining) >= 99.0) return L"Fully Charged";
			} catch (const std::exception&) {
			}
			return L"Plugged In";
		}
		return L"Idle";
	} catch (const std::exception&) {
		return L"";
	}
}

// EstimatedRunTime and TimeToFullCharge both use this magic value to mean "unknown" (e.g. not currently discharging/charging).
std::wstring format_minutes(const std::wstring& raw) {
	if (raw.empty() || raw == L"71582788") return L"";
	try {
		return format_duration(std::stoull(raw) * 60);
	} catch (const std::exception&) {
		return L"";
	}
}

std::wstring format_mv_as_v(const std::wstring& mv_str) {
	if (mv_str.empty()) return L"";
	try {
		wchar_t buf[32];
		swprintf(buf, 32, L"%.1f V", std::stod(mv_str) / 1000.0);
		return buf;
	} catch (const std::exception&) {
		return L"";
	}
}

std::wstring format_mwh_as_wh(const std::wstring& mwh_str) {
	if (mwh_str.empty()) return L"";
	try {
		wchar_t buf[32];
		swprintf(buf, 32, L"%.1f Wh", std::stod(mwh_str) / 1000.0);
		return buf;
	} catch (const std::exception&) {
		return L"";
	}
}

struct capacity_info {
	std::wstring design_wh;
	std::wstring full_wh;
	std::wstring health_percent;
};

// DesignedCapacity/FullChargedCapacity live in ROOT\WMI (exposed by the ACPI battery driver), not Win32_Battery's own DesignCapacity/FullChargeCapacity fields, which are almost always unpopulated on real hardware. Assumes a single battery, like the rest of this provider. Falls back to all-blank if either class is unavailable.
capacity_info battery_capacity_info() {
	try {
		auto design_rows = wmi_connection::instance().query(L"SELECT DesignedCapacity FROM BatteryStaticData", L"ROOT\\WMI");
		auto full_rows = wmi_connection::instance().query(L"SELECT FullChargedCapacity FROM BatteryFullChargedCapacity", L"ROOT\\WMI");
		if (design_rows.empty() || full_rows.empty()) return {};
		std::wstring design_raw = design_rows.front().get(L"DesignedCapacity");
		std::wstring full_raw = full_rows.front().get(L"FullChargedCapacity");
		capacity_info info{format_mwh_as_wh(design_raw), format_mwh_as_wh(full_raw), L""};
		double design = std::stod(design_raw);
		double full = std::stod(full_raw);
		if (design > 0.0) {
			wchar_t buf[16];
			swprintf(buf, 16, L"%.0f%%", (full / design) * 100.0);
			info.health_percent = buf;
		}
		return info;
	} catch (const std::exception&) {
		return {};
	}
}
}  // namespace

class battery_provider : public category_provider {
public:
	std::vector<category_item> get_items() override {
		auto rows = wmi_connection::instance().query(L"SELECT Name, EstimatedChargeRemaining, Chemistry, DesignVoltage, EstimatedRunTime, TimeToFullCharge FROM Win32_Battery");
		std::vector<category_item> items;
		bool single = rows.size() == 1;
		for (const auto& row : rows) {
			category_item item;
			item.label = single ? L"Battery" : (L"Battery, " + row.get(L"Name"));
			auto capacity = battery_capacity_info();
			item.properties = {
				{L"Charge Remaining", with_unit(row.get(L"EstimatedChargeRemaining"), L"%")},
				{L"Status", live_status(row.get(L"EstimatedChargeRemaining"))},
				{L"Battery Health", capacity.health_percent},
				{L"Chemistry", decode_chemistry(row.get(L"Chemistry"))},
				{L"Design Voltage", format_mv_as_v(row.get(L"DesignVoltage"))},
				{L"Design Capacity", capacity.design_wh},
				{L"Full Charge Capacity", capacity.full_wh},
				{L"Estimated Time Remaining", format_minutes(row.get(L"EstimatedRunTime"))},
				{L"Time to Full Charge", format_minutes(row.get(L"TimeToFullCharge"))},
			};
			items.push_back(std::move(item));
		}
		return items;
	}
};
REGISTER_PROVIDER(battery_provider)
