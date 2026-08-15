const std = @import("std");
const wmi = @import("../wmi.zig");
const format = @import("../core/format.zig");
const category_item = @import("../core/category_item.zig");
const CategoryItem = category_item.CategoryItem;
const PropertyRow = category_item.PropertyRow;

pub fn getItems(allocator: std.mem.Allocator) ![]CategoryItem {
	const conn = try wmi.WmiConnection.instance(std.heap.page_allocator);
	const rows = try conn.query(allocator, "SELECT Name, AdapterCompatibility, DriverVersion, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate, AdapterRAM FROM Win32_VideoController", "ROOT\\CIMV2");
	defer for (rows) |*row| row.deinit();
	var items = std.ArrayList(CategoryItem).empty;
	for (rows) |*row| {
		const name = try row.get(allocator, "Name");
		const label = if (rows.len > 1) try std.mem.concat(allocator, u8, &.{ "GPU, ", name }) else "GPU";
		var properties = std.ArrayList(PropertyRow).empty;
		try properties.append(allocator, .{ .name = "Name", .value = name });
		try properties.append(allocator, .{ .name = "Vendor", .value = try row.get(allocator, "AdapterCompatibility") });
		try properties.append(allocator, .{ .name = "Driver Version", .value = try row.get(allocator, "DriverVersion") });
		try properties.append(allocator, .{ .name = "Refresh Rate", .value = try format.withUnit(allocator, try row.get(allocator, "CurrentRefreshRate"), " Hz") });
		try properties.append(allocator, .{ .name = "Video Memory", .value = try format.formatBytes(allocator, try row.get(allocator, "AdapterRAM")) });
		const width = try row.get(allocator, "CurrentHorizontalResolution");
		const height = try row.get(allocator, "CurrentVerticalResolution");
		if (width.len > 0 and height.len > 0) try properties.append(allocator, .{ .name = "Current Resolution", .value = try std.mem.concat(allocator, u8, &.{ width, " x ", height }) });
		try items.append(allocator, .{ .label = label, .properties = try properties.toOwnedSlice(allocator) });
	}
	return items.toOwnedSlice(allocator);
}
