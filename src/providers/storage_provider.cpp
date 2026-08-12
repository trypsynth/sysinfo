#include "core/category_provider.hpp"
#include "core/format.hpp"
#include "core/provider_registry.hpp"
#include "wmi/wmi_connection.hpp"
#include <cwchar>
#include <exception>
#include <unordered_set>

namespace {
std::wstring percent_of(unsigned long long part, unsigned long long whole) {
	if (whole == 0) return L"";
	wchar_t buf[16];
	swprintf(buf, 16, L"%.0f%%", (static_cast<double>(part) / static_cast<double>(whole)) * 100.0);
	return buf;
}

std::wstring used_space_with_percent(const std::wstring& size_str, const std::wstring& free_str) {
	if (size_str.empty() || free_str.empty()) return L"";
	try {
		unsigned long long size = std::stoull(size_str);
		unsigned long long free = std::stoull(free_str);
		if (free > size) return L"";
		unsigned long long used = size - free;
		std::wstring result = format_bytes_as_gb(std::to_wstring(used));
		std::wstring pct = percent_of(used, size);
		if (!pct.empty()) result += L" (" + pct + L")";
		return result;
	} catch (const std::exception&) {
		return L"";
	}
}

std::wstring free_space_with_percent(const std::wstring& size_str, const std::wstring& free_str) {
	if (size_str.empty() || free_str.empty()) return L"";
	try {
		unsigned long long size = std::stoull(size_str);
		unsigned long long free = std::stoull(free_str);
		std::wstring result = format_bytes_as_gb(free_str);
		std::wstring pct = percent_of(free, size);
		if (!pct.empty()) result += L" (" + pct + L")";
		return result;
	} catch (const std::exception&) {
		return L"";
	}
}

// WQL treats backslash as an escape character inside string literals, so a device path like \\.\PHYSICALDRIVE0 has to have every backslash doubled before it can be embedded in a query.
std::wstring escape_wql(const std::wstring& value) {
	std::wstring result;
	for (wchar_t c : value) {
		if (c == L'\\') result += L"\\\\";
		else result += c;
	}
	return result;
}

// There's no direct link between Win32_DiskDrive (physical disks) and Win32_LogicalDisk (drive letters), a disk can hold several partitions, each hosting a volume, so this walks the real association chain: disk to its partitions to each partition's logical disk.
std::vector<wmi_row> volumes_on_disk(const std::wstring& disk_device_id) {
	std::vector<wmi_row> volumes;
	if (disk_device_id.empty()) return volumes;
	try {
		auto partitions = wmi_connection::instance().query(L"ASSOCIATORS OF {Win32_DiskDrive.DeviceID=\"" + escape_wql(disk_device_id) + L"\"} WHERE AssocClass = Win32_DiskDriveToDiskPartition");
		for (const auto& partition : partitions) {
			auto logical_disks = wmi_connection::instance().query(L"ASSOCIATORS OF {Win32_DiskPartition.DeviceID=\"" + escape_wql(partition.get(L"DeviceID")) + L"\"} WHERE AssocClass = Win32_LogicalDiskToPartition");
			for (auto& logical_disk : logical_disks) volumes.push_back(std::move(logical_disk));
		}
	} catch (const std::exception&) {
	}
	return volumes;
}

// prefix disambiguates when a disk has more than one volume (e.g. "C: Total Size", "D: Total Size"); left empty for the common single-volume case.
void append_volume_properties(category_item& item, const wmi_row& volume, const std::wstring& prefix) {
	std::wstring size = volume.get(L"Size");
	std::wstring free = volume.get(L"FreeSpace");
	item.properties.push_back({prefix + L"Total Size", format_bytes_as_gb(size)});
	item.properties.push_back({prefix + L"Used Space", used_space_with_percent(size, free)});
	item.properties.push_back({prefix + L"Free Space", free_space_with_percent(size, free)});
	item.properties.push_back({prefix + L"File System", volume.get(L"FileSystem")});
}
}  // namespace

class storage_provider : public category_provider {
public:
	std::vector<category_item> get_items() override {
		std::vector<category_item> items;
		std::unordered_set<std::wstring> consumed_volumes;

		auto disk_rows = wmi_connection::instance().query(L"SELECT DeviceID, Caption, Model, InterfaceType, MediaType, SerialNumber, Partitions, Status, FirmwareRevision FROM Win32_DiskDrive");
		for (const auto& row : disk_rows) {
			category_item item;
			item.label = L"Storage, " + row.get(L"Caption");
			item.properties = {{L"Model", row.get(L"Model")}, {L"Interface", row.get(L"InterfaceType")}, {L"Media Type", row.get(L"MediaType")}};

			auto volumes = volumes_on_disk(row.get(L"DeviceID"));
			bool single = volumes.size() == 1;
			for (const auto& volume : volumes) {
				std::wstring device_id = volume.get(L"DeviceID");
				consumed_volumes.insert(device_id);
				append_volume_properties(item, volume, single ? L"" : (device_id + L" "));
			}

			item.properties.push_back({L"Partitions", row.get(L"Partitions")});
			item.properties.push_back({L"Health Status", row.get(L"Status")});
			item.properties.push_back({L"Firmware Revision", row.get(L"FirmwareRevision")});
			item.properties.push_back({L"Serial Number", row.get(L"SerialNumber")});
			items.push_back(std::move(item));
		}

		auto volume_rows = wmi_connection::instance().query(L"SELECT DeviceID, VolumeName, FileSystem, Size, FreeSpace FROM Win32_LogicalDisk WHERE DriveType = 3");
		for (const auto& row : volume_rows) {
			std::wstring device_id = row.get(L"DeviceID");
			if (consumed_volumes.count(device_id)) continue;
			std::wstring volume_name = row.get(L"VolumeName");
			category_item item;
			item.label = L"Storage, " + device_id + (volume_name.empty() ? L"" : L" (" + volume_name + L")");
			append_volume_properties(item, row, L"");
			items.push_back(std::move(item));
		}

		// With just one drive there's nothing to tell it apart from, so the model or drive letter suffix is just noise in the category list, drop it there (it's still in the properties as Model).
		if (items.size() == 1) items.front().label = L"Storage";

		return items;
	}
};
REGISTER_PROVIDER(storage_provider)
