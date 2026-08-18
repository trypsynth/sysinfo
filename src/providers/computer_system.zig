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

fn decodeBool(raw: []const u8) []const u8 {
	if (raw.len == 0) return "";
	return if (std.mem.eql(u8, raw, "True")) "Yes" else "No";
}

/// Win32_ComputerSystem has no serial number or UUID of its own, those live on the separate Win32_ComputerSystemProduct class instead (IdentifyingNumber is what OEMs put the service tag/asset serial in). "0" repeated and "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF" are both placeholder UUIDs some boards/VMs report when no real one was ever programmed, so those are treated the same as blank.
fn appendIdentityInfo(allocator: std.mem.Allocator, conn: *wmi.WmiConnection, properties: *std.ArrayList(PropertyRow)) !void {
	const rows = conn.query(allocator, "SELECT IdentifyingNumber, UUID FROM Win32_ComputerSystemProduct", "ROOT\\CIMV2") catch return;
	defer for (rows) |*row| row.deinit();
	if (rows.len == 0) return;
	try properties.append(allocator, .{ .name = "Serial Number", .value = try rows[0].get(allocator, "IdentifyingNumber") });
	const uuid = try rows[0].get(allocator, "UUID");
	if (uuid.len > 0 and !std.ascii.eqlIgnoreCase(uuid, "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")) try properties.append(allocator, .{ .name = "UUID", .value = uuid });
}

pub fn getItems(allocator: std.mem.Allocator) ![]CategoryItem {
	const conn = try wmi.WmiConnection.instance(std.heap.page_allocator);
	const rows = try conn.query(allocator, "SELECT Manufacturer, Model, SystemType, PCSystemType, Domain, PartOfDomain, HypervisorPresent, NumberOfProcessors, NumberOfLogicalProcessors FROM Win32_ComputerSystem", "ROOT\\CIMV2");
	defer for (rows) |*row| row.deinit();
	var items = std.ArrayList(CategoryItem).empty;
	if (rows.len == 0) return items.toOwnedSlice(allocator);
	const row = &rows[0];
	const part_of_domain = std.mem.eql(u8, try row.get(allocator, "PartOfDomain"), "True");
	var properties = std.ArrayList(PropertyRow).empty;
	try properties.append(allocator, .{ .name = "Manufacturer", .value = try row.get(allocator, "Manufacturer") });
	try properties.append(allocator, .{ .name = "Model", .value = try row.get(allocator, "Model") });
	try properties.append(allocator, .{ .name = "Type", .value = decodeSystemType(try row.get(allocator, "PCSystemType")) });
	try properties.append(allocator, .{ .name = "Architecture", .value = try row.get(allocator, "SystemType") });
	try properties.append(allocator, .{ .name = "Processors", .value = try row.get(allocator, "NumberOfProcessors") });
	try properties.append(allocator, .{ .name = "Logical Processors", .value = try row.get(allocator, "NumberOfLogicalProcessors") });
	try properties.append(allocator, .{ .name = "Hypervisor Present", .value = decodeBool(try row.get(allocator, "HypervisorPresent")) });
	try appendIdentityInfo(allocator, conn, &properties);
	try properties.append(allocator, .{ .name = if (part_of_domain) "Domain" else "Workgroup", .value = try row.get(allocator, "Domain") });
	try items.append(allocator, .{ .label = "Computer System", .properties = try properties.toOwnedSlice(allocator) });
	return items.toOwnedSlice(allocator);
}
