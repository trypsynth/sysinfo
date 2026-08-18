const std = @import("std");
const wmi = @import("../wmi.zig");
const format = @import("../core/format.zig");
const category_item = @import("../core/category_item.zig");
const CategoryItem = category_item.CategoryItem;
const PropertyRow = category_item.PropertyRow;

fn usedSpaceWithPercent(allocator: std.mem.Allocator, size_str: []const u8, free_str: []const u8) ![]const u8 {
	if (size_str.len == 0 or free_str.len == 0) return "";
	const size = std.fmt.parseUnsigned(u64, size_str, 10) catch return "";
	const free = std.fmt.parseUnsigned(u64, free_str, 10) catch return "";
	if (free > size) return "";
	const used = size - free;
	var result = try format.formatBytes(allocator, try std.fmt.allocPrint(allocator, "{d}", .{used}));
	const pct = try format.formatPercent(allocator, @floatFromInt(used), @floatFromInt(size));
	if (pct.len > 0) result = try std.fmt.allocPrint(allocator, "{s} ({s})", .{ result, pct });
	return result;
}

fn freeSpaceWithPercent(allocator: std.mem.Allocator, size_str: []const u8, free_str: []const u8) ![]const u8 {
	if (size_str.len == 0 or free_str.len == 0) return "";
	const size = std.fmt.parseUnsigned(u64, size_str, 10) catch return "";
	const free = std.fmt.parseUnsigned(u64, free_str, 10) catch return "";
	var result = try format.formatBytes(allocator, free_str);
	const pct = try format.formatPercent(allocator, @floatFromInt(free), @floatFromInt(size));
	if (pct.len > 0) result = try std.fmt.allocPrint(allocator, "{s} ({s})", .{ result, pct });
	return result;
}

/// WQL treats backslash as an escape character inside string literals, so a device path like \\.\PHYSICALDRIVE0 has to have every backslash doubled before it can be embedded in a query.
fn escapeWql(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
	var result = std.ArrayList(u8).empty;
	for (value) |c| {
		if (c == '\\') try result.appendSlice(allocator, "\\\\") else try result.append(allocator, c);
	}
	return result.toOwnedSlice(allocator);
}

fn decodePhysicalDiskMediaType(raw: []const u8) []const u8 {
	if (std.mem.eql(u8, raw, "3")) return "HDD";
	if (std.mem.eql(u8, raw, "4")) return "SSD";
	if (std.mem.eql(u8, raw, "5")) return "SCM";
	return "";
}

/// MSFT_PhysicalDisk.BusType, a much more specific transport enum than Win32_DiskDrive.InterfaceType's handful of legacy values (IDE/SCSI/USB).
fn decodeBusType(raw: []const u8) []const u8 {
	if (std.mem.eql(u8, raw, "1")) return "SCSI";
	if (std.mem.eql(u8, raw, "2")) return "ATAPI";
	if (std.mem.eql(u8, raw, "3")) return "ATA";
	if (std.mem.eql(u8, raw, "4")) return "IEEE 1394";
	if (std.mem.eql(u8, raw, "6")) return "Fibre Channel";
	if (std.mem.eql(u8, raw, "7")) return "USB";
	if (std.mem.eql(u8, raw, "8")) return "RAID";
	if (std.mem.eql(u8, raw, "9")) return "iSCSI";
	if (std.mem.eql(u8, raw, "10")) return "SAS";
	if (std.mem.eql(u8, raw, "11")) return "SATA";
	if (std.mem.eql(u8, raw, "12")) return "SD";
	if (std.mem.eql(u8, raw, "13")) return "MMC";
	if (std.mem.eql(u8, raw, "15")) return "File Backed Virtual";
	if (std.mem.eql(u8, raw, "16")) return "Storage Spaces";
	if (std.mem.eql(u8, raw, "17")) return "NVMe";
	return "";
}

/// MSFT_PhysicalDisk.HealthStatus is a SMART/Storage-Spaces derived health verdict, a different (and more specific) signal than Win32_DiskDrive.Status's generic OK/Error/Degraded.
fn decodeHealthStatus(raw: []const u8) []const u8 {
	if (std.mem.eql(u8, raw, "0")) return "Healthy";
	if (std.mem.eql(u8, raw, "1")) return "Warning";
	if (std.mem.eql(u8, raw, "2")) return "Unhealthy";
	return "";
}

const PhysicalDiskInfo = struct {
	media_type: []const u8 = "",
	bus_type: []const u8 = "",
	health_status: []const u8 = "",
	rotation_rate: []const u8 = "",
};

/// Win32_DiskDrive.MediaType is almost always just "Fixed hard disk media" for both SSDs and HDDs, it doesn't actually distinguish them, nor does it carry bus type, health, or rotation speed. MSFT_PhysicalDisk (the newer Storage Management WMI provider) does, matched up here by disk index since that's what MSFT_PhysicalDisk.DeviceId holds. Falls back to all blank if the provider isn't available (older Windows).
fn physicalDiskInfo(allocator: std.mem.Allocator, physical_disks: []const wmi.WmiRow, disk_index: []const u8) !PhysicalDiskInfo {
	for (physical_disks) |*disk| {
		if (!std.mem.eql(u8, try disk.get(allocator, "DeviceId"), disk_index)) continue;
		const spindle_speed = try disk.get(allocator, "SpindleSpeed");
		// 0 means non-rotational (SSD), 0xFFFFFFFF/unset means unknown, neither is a real RPM figure worth showing.
		const rotation_rate = if (spindle_speed.len == 0 or std.mem.eql(u8, spindle_speed, "0") or std.mem.eql(u8, spindle_speed, "4294967295")) "" else try format.withUnit(allocator, spindle_speed, " RPM");
		return .{
			.media_type = decodePhysicalDiskMediaType(try disk.get(allocator, "MediaType")),
			.bus_type = decodeBusType(try disk.get(allocator, "BusType")),
			.health_status = decodeHealthStatus(try disk.get(allocator, "HealthStatus")),
			.rotation_rate = rotation_rate,
		};
	}
	return .{};
}

/// There's no direct link between Win32_DiskDrive (physical disks) and Win32_LogicalDisk (drive letters), a disk can hold several partitions, each hosting a volume, so this walks the real association chain (disk to its partitions to each partition's logical disk).
fn volumesOnDisk(allocator: std.mem.Allocator, conn: *wmi.WmiConnection, disk_device_id: []const u8) ![]wmi.WmiRow {
	var volumes = std.ArrayList(wmi.WmiRow).empty;
	if (disk_device_id.len == 0) return volumes.toOwnedSlice(allocator);
	const partitions_query = try std.fmt.allocPrint(allocator, "ASSOCIATORS OF {{Win32_DiskDrive.DeviceID=\"{s}\"}} WHERE AssocClass = Win32_DiskDriveToDiskPartition", .{try escapeWql(allocator, disk_device_id)});
	const partitions = conn.query(allocator, partitions_query, "ROOT\\CIMV2") catch return volumes.toOwnedSlice(allocator);
	defer for (partitions) |*p| p.deinit();
	for (partitions) |*partition| {
		const logical_query = try std.fmt.allocPrint(allocator, "ASSOCIATORS OF {{Win32_DiskPartition.DeviceID=\"{s}\"}} WHERE AssocClass = Win32_LogicalDiskToPartition", .{try escapeWql(allocator, try partition.get(allocator, "DeviceID"))});
		const logical_disks = conn.query(allocator, logical_query, "ROOT\\CIMV2") catch continue;
		for (logical_disks) |logical_disk| try volumes.append(allocator, logical_disk);
	}
	return volumes.toOwnedSlice(allocator);
}

/// prefix disambiguates when a disk has more than one volume (e.g. "C: Total Size", "D: Total Size"), left empty for the common single volume case.
fn appendVolumeProperties(allocator: std.mem.Allocator, properties: *std.ArrayList(PropertyRow), volume: *const wmi.WmiRow, prefix: []const u8) !void {
	const size = try volume.get(allocator, "Size");
	const free = try volume.get(allocator, "FreeSpace");
	try properties.append(allocator, .{ .name = try std.mem.concat(allocator, u8, &.{ prefix, "Total Size" }), .value = try format.formatBytes(allocator, size) });
	try properties.append(allocator, .{ .name = try std.mem.concat(allocator, u8, &.{ prefix, "Used Space" }), .value = try usedSpaceWithPercent(allocator, size, free) });
	try properties.append(allocator, .{ .name = try std.mem.concat(allocator, u8, &.{ prefix, "Free Space" }), .value = try freeSpaceWithPercent(allocator, size, free) });
	try properties.append(allocator, .{ .name = try std.mem.concat(allocator, u8, &.{ prefix, "File System" }), .value = try volume.get(allocator, "FileSystem") });
}

pub fn getItems(allocator: std.mem.Allocator) ![]CategoryItem {
	const conn = try wmi.WmiConnection.instance(std.heap.page_allocator);
	var items = std.ArrayList(CategoryItem).empty;
	var consumed_volumes = std.StringHashMap(void).init(allocator);
	const disk_rows = try conn.query(allocator, "SELECT DeviceID, Caption, Model, InterfaceType, MediaType, Size, SerialNumber, Partitions, Status, FirmwareRevision, Index FROM Win32_DiskDrive", "ROOT\\CIMV2");
	defer for (disk_rows) |*row| row.deinit();
	const physical_disks = conn.query(allocator, "SELECT DeviceId, MediaType, BusType, HealthStatus, SpindleSpeed FROM MSFT_PhysicalDisk", "ROOT\\Microsoft\\Windows\\Storage") catch &.{};
	defer for (physical_disks) |*row| row.deinit();
	for (disk_rows) |*row| {
		const label = try std.mem.concat(allocator, u8, &.{ "Storage, ", try row.get(allocator, "Caption") });
		const disk_info = try physicalDiskInfo(allocator, physical_disks, try row.get(allocator, "Index"));
		var properties = std.ArrayList(PropertyRow).empty;
		try properties.append(allocator, .{ .name = "Model", .value = try row.get(allocator, "Model") });
		try properties.append(allocator, .{ .name = "Interface", .value = try row.get(allocator, "InterfaceType") });
		try properties.append(allocator, .{ .name = "Bus Type", .value = disk_info.bus_type });
		try properties.append(allocator, .{ .name = "Media Type", .value = try row.get(allocator, "MediaType") });
		try properties.append(allocator, .{ .name = "Drive Type", .value = disk_info.media_type });
		try properties.append(allocator, .{ .name = "Rotation Rate", .value = disk_info.rotation_rate });
		const volumes = try volumesOnDisk(allocator, conn, try row.get(allocator, "DeviceID"));
		defer for (volumes) |*v| v.deinit();
		const single = volumes.len == 1;
		// Physical disk capacity is only worth its own line when it isn't already conveyed by a single volume's "Total Size" below (they'd be within a few hundred MB of each other, reserved space aside). Disks with zero or multiple volumes still need it shown explicitly.
		if (!single) try properties.append(allocator, .{ .name = "Capacity", .value = try format.formatBytes(allocator, try row.get(allocator, "Size")) });
		for (volumes) |*volume| {
			const volume_id = try volume.get(allocator, "DeviceID");
			try consumed_volumes.put(volume_id, {});
			const prefix = if (single) "" else try std.mem.concat(allocator, u8, &.{ volume_id, " " });
			try appendVolumeProperties(allocator, &properties, volume, prefix);
		}
		try properties.append(allocator, .{ .name = "Partitions", .value = try row.get(allocator, "Partitions") });
		// MSFT_PhysicalDisk's SMART/Storage-Spaces derived health verdict is more specific than Win32_DiskDrive's generic OK/Error/Degraded status, so it's preferred when available, falling back to the generic one only when the newer provider isn't present (older Windows).
		try properties.append(allocator, .{ .name = "Health Status", .value = if (disk_info.health_status.len > 0) disk_info.health_status else try row.get(allocator, "Status") });
		try properties.append(allocator, .{ .name = "Firmware Revision", .value = try row.get(allocator, "FirmwareRevision") });
		try properties.append(allocator, .{ .name = "Serial Number", .value = try row.get(allocator, "SerialNumber") });
		try items.append(allocator, .{ .label = label, .properties = try properties.toOwnedSlice(allocator) });
	}
	const volume_rows = try conn.query(allocator, "SELECT DeviceID, VolumeName, FileSystem, Size, FreeSpace FROM Win32_LogicalDisk WHERE DriveType = 3", "ROOT\\CIMV2");
	defer for (volume_rows) |*row| row.deinit();
	for (volume_rows) |*row| {
		const device_id = try row.get(allocator, "DeviceID");
		if (consumed_volumes.contains(device_id)) continue;
		const volume_name = try row.get(allocator, "VolumeName");
		const label = if (volume_name.len == 0) try std.mem.concat(allocator, u8, &.{ "Storage, ", device_id }) else try std.fmt.allocPrint(allocator, "Storage, {s} ({s})", .{ device_id, volume_name });
		var properties = std.ArrayList(PropertyRow).empty;
		try appendVolumeProperties(allocator, &properties, row, "");
		try items.append(allocator, .{ .label = label, .properties = try properties.toOwnedSlice(allocator) });
	}
	if (items.items.len == 1) items.items[0].label = "Storage";
	return items.toOwnedSlice(allocator);
}
