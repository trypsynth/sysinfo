const std = @import("std");
const wmi = @import("../wmi.zig");
const category_item = @import("../core/category_item.zig");
const CategoryItem = category_item.CategoryItem;
const PropertyRow = category_item.PropertyRow;

/// PCSystemType says what kind of machine this is. 0 (Unspecified) and anything unmapped falls through to "" (which the existing blank property filtering drops).
fn decodeSystemType(raw: []const u8) []const u8 {
	if (std.mem.eql(u8, raw, "1")) return "Desktop";
	if (std.mem.eql(u8, raw, "2")) return "Laptop";
	if (std.mem.eql(u8, raw, "3")) return "Workstation";
	if (std.mem.eql(u8, raw, "4")) return "Enterprise Server";
	if (std.mem.eql(u8, raw, "5")) return "Small Office Server";
	if (std.mem.eql(u8, raw, "6")) return "Appliance PC";
	if (std.mem.eql(u8, raw, "7")) return "Performance Server";
	if (std.mem.eql(u8, raw, "8")) return "Maximum";
	return "";
}

pub fn getItems(allocator: std.mem.Allocator) ![]CategoryItem {
	const conn = try wmi.WmiConnection.instance(std.heap.page_allocator);
	const rows = try conn.query(allocator, "SELECT Manufacturer, Model, SystemType, PCSystemType, Domain, PartOfDomain FROM Win32_ComputerSystem", "ROOT\\CIMV2");
	defer for (rows) |*row| row.deinit();
	var items = std.ArrayList(CategoryItem).empty;
	if (rows.len == 0) return items.toOwnedSlice(allocator);
	const row = &rows[0];
	const part_of_domain = std.mem.eql(u8, try row.get(allocator, "PartOfDomain"), "True");
	const properties = try allocator.dupe(PropertyRow, &.{
		.{ .name = "Manufacturer", .value = try row.get(allocator, "Manufacturer") },
		.{ .name = "Model", .value = try row.get(allocator, "Model") },
		.{ .name = "Type", .value = decodeSystemType(try row.get(allocator, "PCSystemType")) },
		.{ .name = "Architecture", .value = try row.get(allocator, "SystemType") },
		.{ .name = if (part_of_domain) "Domain" else "Workgroup", .value = try row.get(allocator, "Domain") },
	});
	try items.append(allocator, .{ .label = "Computer System", .properties = properties });
	return items.toOwnedSlice(allocator);
}
