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

/// TPM lives in its own dedicated WMI namespace (only present when a TPM is enumerated at all), so it's queried and appended separately from the rest of BIOS/firmware info, rather than failing the whole category when it's unavailable (e.g. TPM disabled in firmware, or a VM with no virtual TPM).
fn appendTpmInfo(allocator: std.mem.Allocator, conn: *wmi.WmiConnection, properties: *std.ArrayList(PropertyRow)) !void {
	const rows = conn.query(allocator, "SELECT SpecVersion, IsEnabled_InitialValue, IsActivated_InitialValue FROM Win32_Tpm", "ROOT\\CIMV2\\Security\\MicrosoftTpm") catch return;
	defer for (rows) |*row| row.deinit();
	if (rows.len == 0) return;
	const row = &rows[0];
	// SpecVersion is a comma separated list like "2.0, 0, 1.16", the first component is the TPM spec version.
	const spec_version = try row.get(allocator, "SpecVersion");
	const version = if (std.mem.indexOfScalar(u8, spec_version, ',')) |comma| spec_version[0..comma] else spec_version;
	try properties.append(allocator, .{ .name = "TPM Version", .value = version });
	try properties.append(allocator, .{ .name = "TPM Enabled", .value = decodeBool(try row.get(allocator, "IsEnabled_InitialValue")) });
	try properties.append(allocator, .{ .name = "TPM Activated", .value = decodeBool(try row.get(allocator, "IsActivated_InitialValue")) });
}

fn decodeBool(raw: []const u8) []const u8 {
	if (raw.len == 0) return "";
	return if (std.mem.eql(u8, raw, "True")) "Yes" else "No";
}

pub fn getItems(allocator: std.mem.Allocator) ![]CategoryItem {
	const conn = try wmi.WmiConnection.instance(std.heap.page_allocator);
	const rows = try conn.query(allocator, "SELECT Manufacturer, SMBIOSBIOSVersion, SMBIOSMajorVersion, SMBIOSMinorVersion, ReleaseDate, SerialNumber FROM Win32_BIOS", "ROOT\\CIMV2");
	defer for (rows) |*row| row.deinit();
	var items = std.ArrayList(CategoryItem).empty;
	if (rows.len == 0) return items.toOwnedSlice(allocator);
	const row = &rows[0];
	const release_date = try row.get(allocator, "ReleaseDate");
	const smbios_major = try row.get(allocator, "SMBIOSMajorVersion");
	const smbios_minor = try row.get(allocator, "SMBIOSMinorVersion");
	var properties = std.ArrayList(PropertyRow).empty;
	try properties.append(allocator, .{ .name = "Manufacturer", .value = try row.get(allocator, "Manufacturer") });
	try properties.append(allocator, .{ .name = "Version", .value = try row.get(allocator, "SMBIOSBIOSVersion") });
	try properties.append(allocator, .{ .name = "Release Date", .value = try wmi.formatWmiDateTime(allocator, release_date) });
	try properties.append(allocator, .{ .name = "Mode", .value = biosMode() });
	try properties.append(allocator, .{ .name = "Secure Boot", .value = secureBootStatus() });
	if (smbios_major.len > 0 and smbios_minor.len > 0) try properties.append(allocator, .{ .name = "SMBIOS Version", .value = try std.mem.concat(allocator, u8, &.{ smbios_major, ".", smbios_minor }) });
	try appendTpmInfo(allocator, conn, &properties);
	try properties.append(allocator, .{ .name = "Serial Number", .value = try row.get(allocator, "SerialNumber") });
	try items.append(allocator, .{ .label = "BIOS", .properties = try properties.toOwnedSlice(allocator) });
	return items.toOwnedSlice(allocator);
}
