#include "core/category_provider.hpp"
#include "core/format.hpp"
#include "core/provider_registry.hpp"
#include "wmi/wmi_connection.hpp"
#include <cmath>
#include <cwchar>
#include <exception>
#include <windows.h>

namespace {
// EDID text/identifier fields come back as an array of character codes, zero-padded to a fixed length; this decodes them into a plain string, the same convention essentially every WmiMonitorID-reading script uses.
std::wstring decode_edid_string(const std::vector<std::wstring>& codes) {
	std::wstring result;
	for (const auto& code : codes) {
		try {
			int value = std::stoi(code);
			if (value > 0) result += static_cast<wchar_t>(value);
		} catch (const std::exception&) {
		}
	}
	return result;
}

std::wstring screen_size_inches(const std::wstring& width_cm_str, const std::wstring& height_cm_str) {
	if (width_cm_str.empty() || height_cm_str.empty()) return L"";
	try {
		double width_cm = std::stod(width_cm_str);
		double height_cm = std::stod(height_cm_str);
		if (width_cm <= 0.0 || height_cm <= 0.0) return L"";
		wchar_t buf[32];
		swprintf(buf, 32, L"%.1f in", std::sqrt(width_cm * width_cm + height_cm * height_cm) / 2.54);
		return buf;
	} catch (const std::exception&) {
		return L"";
	}
}

// Pulls the PnP hardware ID fragment (e.g. "BOE0C30") out of a device path - EnumDisplayDevices' monitor DeviceID looks like "MONITOR\BOE0C30\{...}\0009", WmiMonitorID's InstanceName looks like "DISPLAY\BOE0C30\5&ea6a3a2&0&UID256_0". Both come from the same EDID-derived PnP ID, so this is what lets the live display driver data (this function's caller) and the WMI/EDID data (the rest of this provider) be matched up for the same physical monitor.
std::wstring extract_hardware_id(const std::wstring& device_path) {
	size_t first = device_path.find(L'\\');
	if (first == std::wstring::npos) return L"";
	size_t second = device_path.find(L'\\', first + 1);
	if (second == std::wstring::npos) return L"";
	return device_path.substr(first + 1, second - first - 1);
}

struct live_display_info {
	std::wstring hardware_id;
	unsigned int width = 0;
	unsigned int height = 0;
	unsigned int refresh_hz = 0;
	bool primary = false;
};

// Win32_DesktopMonitor's ScreenWidth/ScreenHeight are almost always blank; this is the reliable way to get a monitor's actual current resolution and refresh rate, but it's a live display-driver query, not WMI, so it's kept separate from the EDID data above and matched up afterward by hardware ID.
std::vector<live_display_info> enumerate_live_displays() {
	std::vector<live_display_info> result;
	DISPLAY_DEVICEW adapter{};
	adapter.cb = sizeof(adapter);
	for (DWORD adapter_index = 0; EnumDisplayDevicesW(nullptr, adapter_index, &adapter, 0); ++adapter_index) {
		if (!(adapter.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP)) continue;
		DISPLAY_DEVICEW monitor{};
		monitor.cb = sizeof(monitor);
		if (!EnumDisplayDevicesW(adapter.DeviceName, 0, &monitor, 0)) continue;
		DEVMODEW mode{};
		mode.dmSize = sizeof(mode);
		if (!EnumDisplaySettingsW(adapter.DeviceName, ENUM_CURRENT_SETTINGS, &mode)) continue;
		live_display_info info;
		info.hardware_id = extract_hardware_id(monitor.DeviceID);
		info.width = mode.dmPelsWidth;
		info.height = mode.dmPelsHeight;
		info.refresh_hz = mode.dmDisplayFrequency;
		info.primary = (adapter.StateFlags & DISPLAY_DEVICE_PRIMARY_DEVICE) != 0;
		result.push_back(std::move(info));
	}
	return result;
}
}  // namespace

// Win32_DesktopMonitor (ROOT\CIMV2) is almost always sparse on modern hardware - blank manufacturer, blank resolution. WmiMonitorID/WmiMonitorBasicDisplayParams (ROOT\WMI, exposed by the monitor class driver from the panel's own EDID) give real identity and physical size instead; EnumDisplayDevices/EnumDisplaySettings (native Win32, no WMI involved) give the actual live resolution and refresh rate.
class display_provider : public category_provider {
public:
	std::vector<category_item> get_items() override {
		auto id_rows = wmi_connection::instance().query(L"SELECT InstanceName, UserFriendlyName, ManufacturerName, SerialNumberID, WeekOfManufacture, YearOfManufacture FROM WmiMonitorID", L"ROOT\\WMI");

		std::vector<wmi_row> size_rows;
		try {
			size_rows = wmi_connection::instance().query(L"SELECT InstanceName, MaxHorizontalImageSize, MaxVerticalImageSize FROM WmiMonitorBasicDisplayParams", L"ROOT\\WMI");
		} catch (const std::exception&) {
		}

		auto live_displays = enumerate_live_displays();

		std::vector<category_item> items;
		for (const auto& row : id_rows) {
			std::wstring friendly_name = decode_edid_string(row.get_list(L"UserFriendlyName"));
			category_item item;
			item.label = friendly_name.empty() ? L"Display" : (L"Display, " + friendly_name);
			item.properties = {{L"Manufacturer", decode_edid_string(row.get_list(L"ManufacturerName"))}};

			std::wstring instance_name = row.get(L"InstanceName");
			std::wstring hardware_id = extract_hardware_id(instance_name);
			if (!hardware_id.empty()) {
				for (const auto& live : live_displays) {
					if (live.hardware_id != hardware_id) continue;
					item.properties.push_back({L"Resolution", std::to_wstring(live.width) + L" x " + std::to_wstring(live.height)});
					// 0 or 1 is documented as "the display's default rate", not an actual measured Hz value, so it's not worth showing as a number.
					if (live.refresh_hz > 1) item.properties.push_back({L"Refresh Rate", with_unit(std::to_wstring(live.refresh_hz), L" Hz")});
					item.properties.push_back({L"Primary Display", live.primary ? L"Yes" : L"No"});
					break;
				}
			}

			std::wstring serial = decode_edid_string(row.get_list(L"SerialNumberID"));
			// A lone "0" is EDID's conventional placeholder for "no real serial number", not an actual value - exclude it, unlike a genuine multi-digit serial that happens to start with 0.
			if (serial != L"0") item.properties.push_back({L"Serial Number", serial});

			std::wstring week = row.get(L"WeekOfManufacture");
			std::wstring year = row.get(L"YearOfManufacture");
			if (!week.empty() && !year.empty() && week != L"0" && week != L"255") item.properties.push_back({L"Manufacture Date", L"Week " + week + L", " + year});

			for (const auto& size_row : size_rows) {
				if (size_row.get(L"InstanceName") != instance_name) continue;
				std::wstring size = screen_size_inches(size_row.get(L"MaxHorizontalImageSize"), size_row.get(L"MaxVerticalImageSize"));
				if (!size.empty()) item.properties.push_back({L"Screen Size", size});
				break;
			}

			items.push_back(std::move(item));
		}
		return items;
	}
};
REGISTER_PROVIDER(display_provider)
