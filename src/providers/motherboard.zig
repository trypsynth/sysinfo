const std = @import("std");
const wmi = @import("../wmi.zig");
const category_item = @import("../core/category_item.zig");
const CategoryItem = category_item.CategoryItem;
const PropertyRow = category_item.PropertyRow;

pub fn getItems(allocator: std.mem.Allocator) ![]CategoryItem {
	const conn = try wmi.WmiConnection.instance(std.heap.page_allocator);
	const rows = try conn.query(allocator, "SELECT Manufacturer, Product, Version, SerialNumber FROM Win32_BaseBoard", "ROOT\\CIMV2");
	defer for (rows) |*row| row.deinit();
	var items = std.ArrayList(CategoryItem).empty;
	if (rows.len == 0) return items.toOwnedSlice(allocator);
	const row = &rows[0];
	const properties = try allocator.dupe(PropertyRow, &.{
		.{ .name = "Manufacturer", .value = try row.get(allocator, "Manufacturer") },
		.{ .name = "Product", .value = try row.get(allocator, "Product") },
		.{ .name = "Version", .value = try row.get(allocator, "Version") },
		.{ .name = "Serial Number", .value = try row.get(allocator, "SerialNumber") },
	});
	try items.append(allocator, .{ .label = "Motherboard", .properties = properties });
	return items.toOwnedSlice(allocator);
}
