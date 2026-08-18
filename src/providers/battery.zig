const std = @import("std");
const wmi = @import("../wmi.zig");
const format = @import("../core/format.zig");
const category_item = @import("../core/category_item.zig");
const CategoryItem = category_item.CategoryItem;
const PropertyRow = category_item.PropertyRow;

fn decodeChemistry(raw: []const u8) []const u8 {
	if (std.mem.eql(u8, raw, "1")) return "Other";
	if (std.mem.eql(u8, raw, "2")) return "Unknown";
	if (std.mem.eql(u8, raw, "3")) return "Lead Acid";
	if (std.mem.eql(u8, raw, "4")) return "Nickel Cadmium";
	if (std.mem.eql(u8, raw, "5")) return "Nickel Metal Hydride";
	if (std.mem.eql(u8, raw, "6")) return "Lithium-ion";
	if (std.mem.eql(u8, raw, "7")) return "Zinc Air";
	if (std.mem.eql(u8, raw, "8")) return "Lithium Polymer";
	return raw;
}

/// Win32_Battery's own BatteryStatus enum is unreliable on modern hardware, confirmed reporting 2 (Unknown) while plugged in and 1 (Other) while unplugged, neither of which reflects reality. ROOT\WMI's BatteryStatus class (same name, unrelated class, the ACPI battery driver's live status block) gives the real Charging/Discharging/PowerOnline booleans instead, the same fix already applied to capacity below. Plugged in with neither flag set usually means fully charged, but not always (some laptops cap charging below 100 percent for battery health), so that case is cross checked against the actual charge percentage rather than assumed.
fn liveStatus(allocator: std.mem.Allocator, conn: *wmi.WmiConnection, charge_remaining: []const u8) ![]const u8 {
	const rows = conn.query(allocator, "SELECT Charging, Discharging, PowerOnline, Critical FROM BatteryStatus", "ROOT\\WMI") catch return "";
	defer for (rows) |*row| row.deinit();
	if (rows.len == 0) return "";
	const row = &rows[0];
	if (std.mem.eql(u8, try row.get(allocator, "Critical"), "True")) return "Critical";
	if (std.mem.eql(u8, try row.get(allocator, "Charging"), "True")) return "Charging";
	if (std.mem.eql(u8, try row.get(allocator, "Discharging"), "True")) return "Discharging";
	if (std.mem.eql(u8, try row.get(allocator, "PowerOnline"), "True")) {
		if (charge_remaining.len > 0) {
			if (std.fmt.parseFloat(f64, charge_remaining) catch null) |percent| if (percent >= 99.0) return "Fully Charged";
		}
		return "Plugged In";
	}
	return "Idle";
}

/// EstimatedRunTime and TimeToFullCharge both use this magic value to mean "unknown" (e.g. not currently discharging/charging).
fn formatMinutes(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
	if (raw.len == 0 or std.mem.eql(u8, raw, "71582788")) return "";
	const minutes = std.fmt.parseUnsigned(u64, raw, 10) catch return "";
	return format.formatDuration(allocator, minutes * 60);
}

fn formatMvAsV(allocator: std.mem.Allocator, mv_str: []const u8) ![]const u8 {
	if (mv_str.len == 0) return "";
	const mv = std.fmt.parseFloat(f64, mv_str) catch return "";
	return std.fmt.allocPrint(allocator, "{d:.1} V", .{mv / 1000.0});
}

fn formatMwhAsWh(allocator: std.mem.Allocator, mwh_str: []const u8) ![]const u8 {
	if (mwh_str.len == 0) return "";
	const mwh = std.fmt.parseFloat(f64, mwh_str) catch return "";
	return std.fmt.allocPrint(allocator, "{d:.1} Wh", .{mwh / 1000.0});
}

const CapacityInfo = struct {
	design_wh: []const u8 = "",
	full_wh: []const u8 = "",
	health_percent: []const u8 = "",
	manufacturer: []const u8 = "",
	serial_number: []const u8 = "",
	manufacture_date: []const u8 = "",
};

/// ManufactureDate is a packed FAT style date (not a CIM_DATETIME string): bits 0-4 day, bits 5-8 month, bits 9-15 year offset from 1980. Same packing SMBIOS itself uses for this field.
fn decodeFatDate(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
	const value = std.fmt.parseUnsigned(u16, raw, 10) catch return "";
	const day = value & 0x1f;
	const month = (value >> 5) & 0xf;
	const year = 1980 + (value >> 9);
	if (day == 0 or month == 0) return "";
	return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{ year, month, day });
}

/// DesignedCapacity/FullChargedCapacity/ManufactureName/SerialNumber/ManufactureDate live in ROOT\WMI (exposed by the ACPI battery driver), not Win32_Battery's own equivalents (which are almost always unpopulated on real hardware, or in SerialNumber's case a plain integer rather than the vendor's actual serial string). Assumes a single battery, like the rest of this provider. Falls back to all blank if either class is unavailable.
fn batteryCapacityInfo(allocator: std.mem.Allocator, conn: *wmi.WmiConnection) !CapacityInfo {
	const design_rows = conn.query(allocator, "SELECT DesignedCapacity, ManufactureName, SerialNumber, ManufactureDate FROM BatteryStaticData", "ROOT\\WMI") catch return .{};
	defer for (design_rows) |*row| row.deinit();
	const full_rows = conn.query(allocator, "SELECT FullChargedCapacity FROM BatteryFullChargedCapacity", "ROOT\\WMI") catch return .{};
	defer for (full_rows) |*row| row.deinit();
	if (design_rows.len == 0 or full_rows.len == 0) return .{};
	const design_raw = try design_rows[0].get(allocator, "DesignedCapacity");
	const full_raw = try full_rows[0].get(allocator, "FullChargedCapacity");
	const design_val = std.fmt.parseFloat(f64, design_raw) catch return .{};
	const full_val = std.fmt.parseFloat(f64, full_raw) catch return .{};
	return .{
		.design_wh = try formatMwhAsWh(allocator, design_raw),
		.full_wh = try formatMwhAsWh(allocator, full_raw),
		.health_percent = try format.formatPercent(allocator, full_val, design_val),
		.manufacturer = try design_rows[0].get(allocator, "ManufactureName"),
		.serial_number = try design_rows[0].get(allocator, "SerialNumber"),
		.manufacture_date = try decodeFatDate(allocator, try design_rows[0].get(allocator, "ManufactureDate")),
	};
}

/// BatteryCycleCount is its own ROOT\WMI class, not on Win32_Battery or BatteryStaticData.
fn batteryCycleCount(allocator: std.mem.Allocator, conn: *wmi.WmiConnection) ![]const u8 {
	const rows = conn.query(allocator, "SELECT CycleCount FROM BatteryCycleCount", "ROOT\\WMI") catch return "";
	defer for (rows) |*row| row.deinit();
	if (rows.len == 0) return "";
	return rows[0].get(allocator, "CycleCount");
}

pub fn getItems(allocator: std.mem.Allocator) ![]CategoryItem {
	const conn = try wmi.WmiConnection.instance(std.heap.page_allocator);
	const rows = try conn.query(allocator, "SELECT Name, EstimatedChargeRemaining, Chemistry, DesignVoltage, EstimatedRunTime, TimeToFullCharge FROM Win32_Battery", "ROOT\\CIMV2");
	defer for (rows) |*row| row.deinit();
	var items = std.ArrayList(CategoryItem).empty;
	const single = rows.len == 1;
	for (rows) |*row| {
		const label = if (single) "Battery" else try std.mem.concat(allocator, u8, &.{ "Battery, ", try row.get(allocator, "Name") });
		const charge_remaining = try row.get(allocator, "EstimatedChargeRemaining");
		const capacity = try batteryCapacityInfo(allocator, conn);
		const properties = try allocator.dupe(PropertyRow, &.{
			.{ .name = "Charge Remaining", .value = try format.withUnit(allocator, charge_remaining, "%") },
			.{ .name = "Status", .value = try liveStatus(allocator, conn, charge_remaining) },
			.{ .name = "Battery Health", .value = capacity.health_percent },
			.{ .name = "Chemistry", .value = decodeChemistry(try row.get(allocator, "Chemistry")) },
			.{ .name = "Design Voltage", .value = try formatMvAsV(allocator, try row.get(allocator, "DesignVoltage")) },
			.{ .name = "Design Capacity", .value = capacity.design_wh },
			.{ .name = "Full Charge Capacity", .value = capacity.full_wh },
			.{ .name = "Cycle Count", .value = try batteryCycleCount(allocator, conn) },
			.{ .name = "Estimated Time Remaining", .value = try formatMinutes(allocator, try row.get(allocator, "EstimatedRunTime")) },
			.{ .name = "Time to Full Charge", .value = try formatMinutes(allocator, try row.get(allocator, "TimeToFullCharge")) },
			.{ .name = "Manufacturer", .value = capacity.manufacturer },
			.{ .name = "Manufacture Date", .value = capacity.manufacture_date },
			.{ .name = "Serial Number", .value = capacity.serial_number },
		});
		try items.append(allocator, .{ .label = label, .properties = properties });
	}
	return items.toOwnedSlice(allocator);
}
