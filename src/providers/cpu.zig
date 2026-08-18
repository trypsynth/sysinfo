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

/// Win32_Processor.Architecture, not to be confused with SystemType on Win32_ComputerSystem (which is a free text string). 4, 7, 8, 10, 11 are reserved/unused by Microsoft's own docs, anything unmapped falls through to "".
fn decodeArchitecture(raw: []const u8) []const u8 {
	if (std.mem.eql(u8, raw, "0")) return "x86";
	if (std.mem.eql(u8, raw, "1")) return "MIPS";
	if (std.mem.eql(u8, raw, "2")) return "Alpha";
	if (std.mem.eql(u8, raw, "3")) return "PowerPC";
	if (std.mem.eql(u8, raw, "5")) return "ARM";
	if (std.mem.eql(u8, raw, "6")) return "IA64";
	if (std.mem.eql(u8, raw, "9")) return "x64";
	if (std.mem.eql(u8, raw, "12")) return "ARM64";
	return "";
}

/// CurrentVoltage is a legacy SMBIOS Processor Information field: when bit 7 (0x80) is set, bits 0-6 hold the actual voltage in tenths of a volt. When bit 7 is clear, the value is instead an index into a hardcoded legacy VRM setting table (pre-dates on-die voltage reporting), which isn't a real voltage reading, so that case is left blank rather than guessed at.
fn decodeVoltage(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
	const value = std.fmt.parseUnsigned(u16, raw, 10) catch return "";
	if (value & 0x80 == 0) return "";
	const tenths_of_volt = value & 0x7f;
	return std.fmt.allocPrint(allocator, "{d}.{d} V", .{ tenths_of_volt / 10, tenths_of_volt % 10 });
}

fn hyperThreading(cores: []const u8, logical: []const u8) []const u8 {
	const core_count = std.fmt.parseUnsigned(u32, cores, 10) catch return "";
	const logical_count = std.fmt.parseUnsigned(u32, logical, 10) catch return "";
	if (core_count == 0) return "";
	return if (logical_count > core_count) "Yes" else "No";
}

/// Win32_Processor has no L1 cache size property at all, unlike L2/L3. Win32_CacheMemory (Level = 3, the enum value for "Level 1") is the only place it's exposed, and a CPU can report separate L1 data/instruction cache entries, so this sums every Level 1 entry's InstalledSize (KB) rather than assuming exactly one row.
fn l1CacheSize(allocator: std.mem.Allocator, conn: *wmi.WmiConnection) ![]const u8 {
	const rows = conn.query(allocator, "SELECT InstalledSize FROM Win32_CacheMemory WHERE Level = 3", "ROOT\\CIMV2") catch return "";
	defer for (rows) |*row| row.deinit();
	if (rows.len == 0) return "";
	var total: u64 = 0;
	for (rows) |*row| total += std.fmt.parseUnsigned(u64, try row.get(allocator, "InstalledSize"), 10) catch 0;
	if (total == 0) return "";
	return format.withUnit(allocator, try std.fmt.allocPrint(allocator, "{d}", .{total}), " KB");
}

pub fn getItems(allocator: std.mem.Allocator) ![]CategoryItem {
	const conn = try wmi.WmiConnection.instance(std.heap.page_allocator);
	const rows = try conn.query(allocator, "SELECT Name, Manufacturer, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, CurrentClockSpeed, ExtClock, CurrentVoltage, LoadPercentage, Architecture, L2CacheSize, L3CacheSize, SocketDesignation, AddressWidth, VirtualizationFirmwareEnabled, ProcessorId FROM Win32_Processor", "ROOT\\CIMV2");
	defer for (rows) |*row| row.deinit();
	var items = std.ArrayList(CategoryItem).empty;
	for (rows) |*row| {
		const name = try row.get(allocator, "Name");
		const label = if (rows.len > 1) try std.mem.concat(allocator, u8, &.{ "Processor, ", name }) else "Processor";
		const cores = try row.get(allocator, "NumberOfCores");
		const logical_processors = try row.get(allocator, "NumberOfLogicalProcessors");
		const properties = try allocator.dupe(PropertyRow, &.{
			.{ .name = "Name", .value = name },
			.{ .name = "Manufacturer", .value = try row.get(allocator, "Manufacturer") },
			.{ .name = "Architecture", .value = decodeArchitecture(try row.get(allocator, "Architecture")) },
			.{ .name = "Socket", .value = try row.get(allocator, "SocketDesignation") },
			.{ .name = "Cores", .value = cores },
			.{ .name = "Logical Processors", .value = logical_processors },
			.{ .name = "Hyper-Threading", .value = hyperThreading(cores, logical_processors) },
			.{ .name = "Max Clock Speed", .value = try format.withUnit(allocator, try row.get(allocator, "MaxClockSpeed"), " MHz") },
			.{ .name = "Current Clock Speed", .value = try format.withUnit(allocator, try row.get(allocator, "CurrentClockSpeed"), " MHz") },
			.{ .name = "Bus Speed", .value = try format.withUnit(allocator, try row.get(allocator, "ExtClock"), " MHz") },
			.{ .name = "Voltage", .value = try decodeVoltage(allocator, try row.get(allocator, "CurrentVoltage")) },
			.{ .name = "Current Load", .value = try format.withUnit(allocator, try row.get(allocator, "LoadPercentage"), "%") },
			.{ .name = "L1 Cache", .value = try l1CacheSize(allocator, conn) },
			.{ .name = "L2 Cache", .value = try format.withUnit(allocator, try row.get(allocator, "L2CacheSize"), " KB") },
			.{ .name = "L3 Cache", .value = try format.withUnit(allocator, try row.get(allocator, "L3CacheSize"), " KB") },
			.{ .name = "Address Width", .value = try format.withUnit(allocator, try row.get(allocator, "AddressWidth"), "-bit") },
			.{ .name = "Virtualization Enabled", .value = decodeBool(try row.get(allocator, "VirtualizationFirmwareEnabled")) },
			.{ .name = "Processor ID", .value = try row.get(allocator, "ProcessorId") },
		});
		try items.append(allocator, .{ .label = label, .properties = properties });
	}
	return items.toOwnedSlice(allocator);
}
