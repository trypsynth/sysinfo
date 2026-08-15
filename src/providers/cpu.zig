const std = @import("std");
const wmi = @import("../wmi.zig");
const format = @import("../core/format.zig");
const category_item = @import("../core/category_item.zig");
const CategoryItem = category_item.CategoryItem;
const PropertyRow = category_item.PropertyRow;

fn decodeBool(raw: []const u8) []const u8 {
	if (raw.len == 0) return "";
	return if (std.mem.eql(u8, raw, "True")) "Yes" else "No";
}

pub fn getItems(allocator: std.mem.Allocator) ![]CategoryItem {
	const conn = try wmi.WmiConnection.instance(std.heap.page_allocator);
	const rows = try conn.query(allocator, "SELECT Name, Manufacturer, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, L2CacheSize, L3CacheSize, SocketDesignation, VirtualizationFirmwareEnabled FROM Win32_Processor", "ROOT\\CIMV2");
	defer for (rows) |*row| row.deinit();
	var items = std.ArrayList(CategoryItem).empty;
	for (rows) |*row| {
		const name = try row.get(allocator, "Name");
		const label = if (rows.len > 1) try std.mem.concat(allocator, u8, &.{ "Processor, ", name }) else "Processor";
		const properties = try allocator.dupe(PropertyRow, &.{
			.{ .name = "Name", .value = name },
			.{ .name = "Manufacturer", .value = try row.get(allocator, "Manufacturer") },
			.{ .name = "Socket", .value = try row.get(allocator, "SocketDesignation") },
			.{ .name = "Cores", .value = try row.get(allocator, "NumberOfCores") },
			.{ .name = "Logical Processors", .value = try row.get(allocator, "NumberOfLogicalProcessors") },
			.{ .name = "Max Clock Speed", .value = try format.withUnit(allocator, try row.get(allocator, "MaxClockSpeed"), " MHz") },
			.{ .name = "L2 Cache", .value = try format.withUnit(allocator, try row.get(allocator, "L2CacheSize"), " KB") },
			.{ .name = "L3 Cache", .value = try format.withUnit(allocator, try row.get(allocator, "L3CacheSize"), " KB") },
			.{ .name = "Virtualization Enabled", .value = decodeBool(try row.get(allocator, "VirtualizationFirmwareEnabled")) },
		});
		try items.append(allocator, .{ .label = label, .properties = properties });
	}
	return items.toOwnedSlice(allocator);
}
