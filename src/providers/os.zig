const std = @import("std");
const win32 = @import("../win32.zig");
const wmi = @import("../wmi.zig");
const format = @import("../core/format.zig");
const category_item = @import("../core/category_item.zig");
const CategoryItem = category_item.CategoryItem;
const PropertyRow = category_item.PropertyRow;

pub fn getItems(allocator: std.mem.Allocator) ![]CategoryItem {
	const conn = try wmi.WmiConnection.instance(std.heap.page_allocator);
	const rows = try conn.query(allocator, "SELECT Caption, Version, BuildNumber, OSArchitecture, InstallDate, LastBootUpTime, SerialNumber, RegisteredUser, CSName, WindowsDirectory, SystemDirectory, SystemDrive, NumberOfProcesses, NumberOfUsers FROM Win32_OperatingSystem", "ROOT\\CIMV2");
	defer for (rows) |*row| row.deinit();
	var items = std.ArrayList(CategoryItem).empty;
	if (rows.len == 0) return items.toOwnedSlice(allocator);
	const row = &rows[0];
	const install_date = try row.get(allocator, "InstallDate");
	const last_boot = try row.get(allocator, "LastBootUpTime");
	const properties = try allocator.dupe(PropertyRow, &.{
		.{ .name = "Name", .value = try row.get(allocator, "Caption") },
		.{ .name = "Computer Name", .value = try row.get(allocator, "CSName") },
		.{ .name = "Version", .value = try row.get(allocator, "Version") },
		.{ .name = "Build Number", .value = try row.get(allocator, "BuildNumber") },
		.{ .name = "Architecture", .value = try row.get(allocator, "OSArchitecture") },
		.{ .name = "Install Date", .value = try wmi.formatWmiDateTime(allocator, install_date) },
		.{ .name = "Last Boot", .value = try wmi.formatWmiDateTime(allocator, last_boot) },
		.{ .name = "Uptime", .value = try format.formatDuration(allocator, win32.GetTickCount64() / 1000) },
		.{ .name = "Registered User", .value = try row.get(allocator, "RegisteredUser") },
		.{ .name = "Serial Number", .value = try row.get(allocator, "SerialNumber") },
		.{ .name = "Windows Directory", .value = try row.get(allocator, "WindowsDirectory") },
		.{ .name = "System Directory", .value = try row.get(allocator, "SystemDirectory") },
		.{ .name = "System Drive", .value = try row.get(allocator, "SystemDrive") },
		.{ .name = "Running Processes", .value = try row.get(allocator, "NumberOfProcesses") },
		.{ .name = "Logged-on Users", .value = try row.get(allocator, "NumberOfUsers") },
	});
	try items.append(allocator, .{ .label = "Operating System", .properties = properties });
	return items.toOwnedSlice(allocator);
}
