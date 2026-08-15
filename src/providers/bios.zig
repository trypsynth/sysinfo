const std = @import("std");
const win32 = @import("../win32.zig");
const wmi = @import("../wmi.zig");
const category_item = @import("../core/category_item.zig");
const CategoryItem = category_item.CategoryItem;
const PropertyRow = category_item.PropertyRow;

fn biosMode() []const u8 {
	var firmware_type: u32 = win32.FIRMWARE_TYPE_UNKNOWN;
	if (win32.GetFirmwareType(&firmware_type) == 0) return "";
	if (firmware_type == win32.FIRMWARE_TYPE_UEFI) return "UEFI";
	if (firmware_type == win32.FIRMWARE_TYPE_BIOS) return "Legacy";
	return "";
}

/// Only meaningful under UEFI, the key simply doesn't exist on Legacy BIOS systems (treated the same as "can't determine" and left blank).
fn secureBootStatus() []const u8 {
	var value: win32.DWORD = 0;
	var size: win32.DWORD = @sizeOf(win32.DWORD);
	const status = win32.RegGetValueW(win32.HKEY_LOCAL_MACHINE, std.unicode.utf8ToUtf16LeStringLiteral("SYSTEM\\CurrentControlSet\\Control\\SecureBoot\\State"), std.unicode.utf8ToUtf16LeStringLiteral("UEFISecureBootEnabled"), win32.RRF_RT_REG_DWORD, null, &value, &size);
	if (status != win32.ERROR_SUCCESS) return "";
	return if (value != 0) "Enabled" else "Disabled";
}

pub fn getItems(allocator: std.mem.Allocator) ![]CategoryItem {
	const conn = try wmi.WmiConnection.instance(std.heap.page_allocator);
	const rows = try conn.query(allocator, "SELECT Manufacturer, SMBIOSBIOSVersion, ReleaseDate, SerialNumber FROM Win32_BIOS", "ROOT\\CIMV2");
	defer for (rows) |*row| row.deinit();
	var items = std.ArrayList(CategoryItem).empty;
	if (rows.len == 0) return items.toOwnedSlice(allocator);
	const row = &rows[0];
	const release_date = try row.get(allocator, "ReleaseDate");
	const properties = try allocator.dupe(PropertyRow, &.{
		.{ .name = "Manufacturer", .value = try row.get(allocator, "Manufacturer") },
		.{ .name = "Version", .value = try row.get(allocator, "SMBIOSBIOSVersion") },
		.{ .name = "Release Date", .value = try wmi.formatWmiDateTime(allocator, release_date) },
		.{ .name = "Mode", .value = biosMode() },
		.{ .name = "Secure Boot", .value = secureBootStatus() },
		.{ .name = "Serial Number", .value = try row.get(allocator, "SerialNumber") },
	});
	try items.append(allocator, .{ .label = "BIOS", .properties = properties });
	return items.toOwnedSlice(allocator);
}
