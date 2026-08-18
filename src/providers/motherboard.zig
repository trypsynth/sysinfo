const std = @import("std");
const wmi = @import("../wmi.zig");
const category_item = @import("../core/category_item.zig");
const CategoryItem = category_item.CategoryItem;
const PropertyRow = category_item.PropertyRow;

/// SMBIOS System Enclosure Type values (a much larger, more physically specific set than Win32_ComputerSystem.PCSystemType). 0 and anything unmapped falls through to "".
fn decodeChassisType(raw: []const u8) []const u8 {
	if (std.mem.eql(u8, raw, "3")) return "Desktop";
	if (std.mem.eql(u8, raw, "4")) return "Low Profile Desktop";
	if (std.mem.eql(u8, raw, "5")) return "Pizza Box";
	if (std.mem.eql(u8, raw, "6")) return "Mini Tower";
	if (std.mem.eql(u8, raw, "7")) return "Tower";
	if (std.mem.eql(u8, raw, "8")) return "Portable";
	if (std.mem.eql(u8, raw, "9")) return "Laptop";
	if (std.mem.eql(u8, raw, "10")) return "Notebook";
	if (std.mem.eql(u8, raw, "11")) return "Handheld";
	if (std.mem.eql(u8, raw, "12")) return "Docking Station";
	if (std.mem.eql(u8, raw, "13")) return "All in One";
	if (std.mem.eql(u8, raw, "14")) return "Sub Notebook";
	if (std.mem.eql(u8, raw, "15")) return "Space-saving";
	if (std.mem.eql(u8, raw, "16")) return "Lunch Box";
	if (std.mem.eql(u8, raw, "17")) return "Main Server Chassis";
	if (std.mem.eql(u8, raw, "18")) return "Expansion Chassis";
	if (std.mem.eql(u8, raw, "23")) return "Rack Mount Chassis";
	if (std.mem.eql(u8, raw, "30")) return "Tablet";
	if (std.mem.eql(u8, raw, "31")) return "Convertible";
	if (std.mem.eql(u8, raw, "32")) return "Detachable";
	return "";
}

/// Chassis/enclosure info lives on a separate class from the baseboard itself, appended here rather than as its own category since "which physical box is this motherboard in" is naturally part of describing the board.
fn appendChassisInfo(allocator: std.mem.Allocator, conn: *wmi.WmiConnection, properties: *std.ArrayList(PropertyRow)) !void {
	const rows = conn.query(allocator, "SELECT ChassisTypes, SMBIOSAssetTag FROM Win32_SystemEnclosure", "ROOT\\CIMV2") catch return;
	defer for (rows) |*row| row.deinit();
	if (rows.len == 0) return;
	const chassis_types = try rows[0].getList(allocator, "ChassisTypes");
	if (chassis_types.len > 0) try properties.append(allocator, .{ .name = "Chassis Type", .value = decodeChassisType(chassis_types[0]) });
	// Most OEMs leave this an unset run of spaces rather than a truly empty string, trim so the blank filtering elsewhere still catches it.
	try properties.append(allocator, .{ .name = "Asset Tag", .value = std.mem.trim(u8, try rows[0].get(allocator, "SMBIOSAssetTag"), " ") });
}

pub fn getItems(allocator: std.mem.Allocator) ![]CategoryItem {
	const conn = try wmi.WmiConnection.instance(std.heap.page_allocator);
	const rows = try conn.query(allocator, "SELECT Manufacturer, Product, Version, SerialNumber FROM Win32_BaseBoard", "ROOT\\CIMV2");
	defer for (rows) |*row| row.deinit();
	var items = std.ArrayList(CategoryItem).empty;
	if (rows.len == 0) return items.toOwnedSlice(allocator);
	const row = &rows[0];
	var properties = std.ArrayList(PropertyRow).empty;
	try properties.append(allocator, .{ .name = "Manufacturer", .value = try row.get(allocator, "Manufacturer") });
	try properties.append(allocator, .{ .name = "Product", .value = try row.get(allocator, "Product") });
	try properties.append(allocator, .{ .name = "Version", .value = try row.get(allocator, "Version") });
	try appendChassisInfo(allocator, conn, &properties);
	try properties.append(allocator, .{ .name = "Serial Number", .value = try row.get(allocator, "SerialNumber") });
	try items.append(allocator, .{ .label = "Motherboard", .properties = try properties.toOwnedSlice(allocator) });
	return items.toOwnedSlice(allocator);
}
