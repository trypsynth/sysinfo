const std = @import("std");
const win32 = @import("../win32.zig");
const wmi = @import("../wmi.zig");
const format = @import("../core/format.zig");
const category_item = @import("../core/category_item.zig");
const CategoryItem = category_item.CategoryItem;
const PropertyRow = category_item.PropertyRow;

fn formatKbAsGb(allocator: std.mem.Allocator, kb: u64) ![]const u8 {
	const bytes_str = try std.fmt.allocPrint(allocator, "{d}", .{kb * 1024});
	return format.formatBytes(allocator, bytes_str);
}

/// SMBIOSMemoryType is a raw SMBIOS Memory Device Type byte, Microsoft's own docs only officially list values up to 26 (DDR4), but real hardware reports the newer SMBIOS spec values for DDR5 and beyond too. 0 (Unknown) and anything not confidently mapped falls through to "" (which the existing blank property filtering drops).
fn decodeMemoryType(raw: []const u8) []const u8 {
	if (std.mem.eql(u8, raw, "17")) return "SDRAM";
	if (std.mem.eql(u8, raw, "19")) return "RDRAM";
	if (std.mem.eql(u8, raw, "20")) return "DDR";
	if (std.mem.eql(u8, raw, "21")) return "DDR2";
	if (std.mem.eql(u8, raw, "22")) return "DDR2 FB-DIMM";
	if (std.mem.eql(u8, raw, "24")) return "DDR3";
	if (std.mem.eql(u8, raw, "25")) return "FBD2";
	if (std.mem.eql(u8, raw, "26")) return "DDR4";
	if (std.mem.eql(u8, raw, "27")) return "LPDDR";
	if (std.mem.eql(u8, raw, "28")) return "LPDDR2";
	if (std.mem.eql(u8, raw, "29")) return "LPDDR3";
	if (std.mem.eql(u8, raw, "30")) return "LPDDR4";
	if (std.mem.eql(u8, raw, "32")) return "HBM";
	if (std.mem.eql(u8, raw, "33")) return "HBM2";
	if (std.mem.eql(u8, raw, "34")) return "DDR5";
	if (std.mem.eql(u8, raw, "35")) return "LPDDR5";
	return "";
}

fn decodeFormFactor(raw: []const u8) []const u8 {
	if (std.mem.eql(u8, raw, "7")) return "SIMM";
	if (std.mem.eql(u8, raw, "8")) return "DIMM";
	if (std.mem.eql(u8, raw, "11")) return "RIMM";
	if (std.mem.eql(u8, raw, "12")) return "SODIMM";
	if (std.mem.eql(u8, raw, "13")) return "SRIMM";
	return "";
}

pub fn getItems(allocator: std.mem.Allocator) ![]CategoryItem {
	const conn = try wmi.WmiConnection.instance(std.heap.page_allocator);
	var items = std.ArrayList(CategoryItem).empty;
	var summary_properties = std.ArrayList(PropertyRow).empty;
	var installed_kb: u64 = 0;
	const have_installed = win32.GetPhysicallyInstalledSystemMemory(&installed_kb) != 0;
	if (have_installed) try summary_properties.append(allocator, .{ .name = "Physically Installed", .value = try formatKbAsGb(allocator, installed_kb) });
	const os_rows = try conn.query(allocator, "SELECT TotalVisibleMemorySize, FreePhysicalMemory FROM Win32_OperatingSystem", "ROOT\\CIMV2");
	defer for (os_rows) |*row| row.deinit();
	if (os_rows.len > 0) {
		const visible_str = try os_rows[0].get(allocator, "TotalVisibleMemorySize");
		if (std.fmt.parseUnsigned(u64, visible_str, 10) catch null) |visible_kb| {
			try summary_properties.append(allocator, .{ .name = "Available to Windows", .value = try formatKbAsGb(allocator, visible_kb) });
			if (have_installed and installed_kb > visible_kb) try summary_properties.append(allocator, .{ .name = "Hardware Reserved", .value = try formatKbAsGb(allocator, installed_kb - visible_kb) });
		}
		const free_str = try os_rows[0].get(allocator, "FreePhysicalMemory");
		if (std.fmt.parseUnsigned(u64, free_str, 10) catch null) |free_kb| try summary_properties.append(allocator, .{ .name = "Free", .value = try formatKbAsGb(allocator, free_kb) });
	}
	try items.append(allocator, .{ .label = "Memory, Summary", .properties = try summary_properties.toOwnedSlice(allocator) });
	const module_rows = try conn.query(allocator, "SELECT DeviceLocator, BankLabel, Capacity, Speed, Manufacturer, SMBIOSMemoryType, FormFactor FROM Win32_PhysicalMemory", "ROOT\\CIMV2");
	defer for (module_rows) |*row| row.deinit();
	for (module_rows) |*row| {
		const locator = try row.get(allocator, "DeviceLocator");
		const label = if (locator.len == 0) "Memory, Module" else try std.mem.concat(allocator, u8, &.{ "Memory, ", locator });
		const properties = try allocator.dupe(PropertyRow, &.{
			.{ .name = "Bank", .value = try row.get(allocator, "BankLabel") },
			.{ .name = "Type", .value = decodeMemoryType(try row.get(allocator, "SMBIOSMemoryType")) },
			.{ .name = "Form Factor", .value = decodeFormFactor(try row.get(allocator, "FormFactor")) },
			.{ .name = "Capacity", .value = try format.formatBytes(allocator, try row.get(allocator, "Capacity")) },
			.{ .name = "Speed", .value = try format.withUnit(allocator, try row.get(allocator, "Speed"), " MHz") },
			.{ .name = "Manufacturer", .value = try row.get(allocator, "Manufacturer") },
		});
		try items.append(allocator, .{ .label = label, .properties = properties });
	}
	return items.toOwnedSlice(allocator);
}
