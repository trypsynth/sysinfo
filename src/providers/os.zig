const std = @import("std");
const win32 = @import("../win32.zig");
const wmi = @import("../wmi.zig");
const format = @import("../core/format.zig");
const category_item = @import("../core/category_item.zig");
const CategoryItem = category_item.CategoryItem;
const PropertyRow = category_item.PropertyRow;

/// Win32_TimeZone is its own class, not a property on Win32_OperatingSystem.
fn timeZoneCaption(allocator: std.mem.Allocator, conn: *wmi.WmiConnection) ![]const u8 {
	const rows = conn.query(allocator, "SELECT Caption FROM Win32_TimeZone", "ROOT\\CIMV2") catch return "";
	defer for (rows) |*row| row.deinit();
	if (rows.len == 0) return "";
	return rows[0].get(allocator, "Caption");
}

/// Page file sizing lives on Win32_PageFileUsage (one row per page file, sized in MB), not on Win32_OperatingSystem. Systems with multiple page files (uncommon but possible) have their allocated size summed; only the first file's path is shown as a representative name.
fn pageFileInfo(allocator: std.mem.Allocator, conn: *wmi.WmiConnection) !struct { size: []const u8 = "", name: []const u8 = "" } {
	const rows = conn.query(allocator, "SELECT Name, AllocatedBaseSize FROM Win32_PageFileUsage", "ROOT\\CIMV2") catch return .{};
	defer for (rows) |*row| row.deinit();
	if (rows.len == 0) return .{};
	var total_mb: u64 = 0;
	for (rows) |*row| total_mb += std.fmt.parseUnsigned(u64, try row.get(allocator, "AllocatedBaseSize"), 10) catch 0;
	if (total_mb == 0) return .{ .name = try rows[0].get(allocator, "Name") };
	return .{ .size = try format.formatBytes(allocator, try std.fmt.allocPrint(allocator, "{d}", .{total_mb * 1024 * 1024})), .name = try rows[0].get(allocator, "Name") };
}

pub fn getItems(allocator: std.mem.Allocator) ![]CategoryItem {
	const conn = try wmi.WmiConnection.instance(std.heap.page_allocator);
	const rows = try conn.query(allocator, "SELECT Caption, Version, BuildNumber, OSArchitecture, InstallDate, LastBootUpTime, SerialNumber, RegisteredUser, CSName, WindowsDirectory, SystemDirectory, SystemDrive, BootDevice, NumberOfProcesses, NumberOfUsers FROM Win32_OperatingSystem", "ROOT\\CIMV2");
	defer for (rows) |*row| row.deinit();
	var items = std.ArrayList(CategoryItem).empty;
	if (rows.len == 0) return items.toOwnedSlice(allocator);
	const row = &rows[0];
	const install_date = try row.get(allocator, "InstallDate");
	const last_boot = try row.get(allocator, "LastBootUpTime");
	const page_file = try pageFileInfo(allocator, conn);
	var properties = std.ArrayList(PropertyRow).empty;
	try properties.append(allocator, .{ .name = "Name", .value = try row.get(allocator, "Caption") });
	try properties.append(allocator, .{ .name = "Computer Name", .value = try row.get(allocator, "CSName") });
	try properties.append(allocator, .{ .name = "Version", .value = try row.get(allocator, "Version") });
	try properties.append(allocator, .{ .name = "Build Number", .value = try row.get(allocator, "BuildNumber") });
	try properties.append(allocator, .{ .name = "Architecture", .value = try row.get(allocator, "OSArchitecture") });
	try properties.append(allocator, .{ .name = "Install Date", .value = try wmi.formatWmiDateTime(allocator, install_date) });
	try properties.append(allocator, .{ .name = "Last Boot", .value = try wmi.formatWmiDateTime(allocator, last_boot) });
	try properties.append(allocator, .{ .name = "Uptime", .value = try format.formatDuration(allocator, win32.GetTickCount64() / 1000) });
	try properties.append(allocator, .{ .name = "Time Zone", .value = try timeZoneCaption(allocator, conn) });
	try properties.append(allocator, .{ .name = "Registered User", .value = try row.get(allocator, "RegisteredUser") });
	try properties.append(allocator, .{ .name = "Serial Number", .value = try row.get(allocator, "SerialNumber") });
	try properties.append(allocator, .{ .name = "Windows Directory", .value = try row.get(allocator, "WindowsDirectory") });
	try properties.append(allocator, .{ .name = "System Directory", .value = try row.get(allocator, "SystemDirectory") });
	try properties.append(allocator, .{ .name = "System Drive", .value = try row.get(allocator, "SystemDrive") });
	try properties.append(allocator, .{ .name = "Boot Device", .value = try row.get(allocator, "BootDevice") });
	try properties.append(allocator, .{ .name = "Page File", .value = page_file.name });
	try properties.append(allocator, .{ .name = "Page File Size", .value = page_file.size });
	try properties.append(allocator, .{ .name = "Running Processes", .value = try row.get(allocator, "NumberOfProcesses") });
	try properties.append(allocator, .{ .name = "Logged-on Users", .value = try row.get(allocator, "NumberOfUsers") });
	try items.append(allocator, .{ .label = "Operating System", .properties = try properties.toOwnedSlice(allocator) });
	return items.toOwnedSlice(allocator);
}
