const std = @import("std");
const win32 = @import("../win32.zig");
const wmi = @import("../wmi.zig");
const format = @import("../core/format.zig");
const category_item = @import("../core/category_item.zig");
const CategoryItem = category_item.CategoryItem;
const PropertyRow = category_item.PropertyRow;

/// EDID text/identifier fields come back as an array of character codes, zero padded to a fixed length, this decodes them into a plain string (the same convention essentially every WmiMonitorID reading script uses).
fn decodeEdidString(allocator: std.mem.Allocator, codes: []const []const u8) ![]const u8 {
	var result = std.ArrayList(u8).empty;
	for (codes) |code| {
		const value = std.fmt.parseInt(i32, code, 10) catch continue;
		if (value > 0) try result.append(allocator, @intCast(value));
	}
	return result.toOwnedSlice(allocator);
}

fn screenSizeInches(allocator: std.mem.Allocator, width_cm_str: []const u8, height_cm_str: []const u8) ![]const u8 {
	if (width_cm_str.len == 0 or height_cm_str.len == 0) return "";
	const width_cm = std.fmt.parseFloat(f64, width_cm_str) catch return "";
	const height_cm = std.fmt.parseFloat(f64, height_cm_str) catch return "";
	if (width_cm <= 0.0 or height_cm <= 0.0) return "";
	return std.fmt.allocPrint(allocator, "{d:.1} in", .{std.math.sqrt(width_cm * width_cm + height_cm * height_cm) / 2.54});
}

/// Pulls the PnP hardware ID fragment (e.g. "BOE0C30") out of a device path, EnumDisplayDevices' monitor DeviceID looks like "MONITOR\BOE0C30\{...}\0009", WmiMonitorID's InstanceName looks like "DISPLAY\BOE0C30\5&ea6a3a2&0&UID256_0". Both come from the same EDID derived PnP ID, so this is what lets the live display driver data and the WMI/EDID data be matched up for the same physical monitor.
fn extractHardwareId(device_path: []const u8) []const u8 {
	const first = std.mem.indexOfScalar(u8, device_path, '\\') orelse return "";
	const second = std.mem.indexOfScalarPos(u8, device_path, first + 1, '\\') orelse return "";
	return device_path[first + 1 .. second];
}

fn wideToUtf8(allocator: std.mem.Allocator, wide: [*:0]const u16) ![]const u8 {
	var len: usize = 0;
	while (wide[len] != 0) : (len += 1) {}
	return std.unicode.utf16LeToUtf8Alloc(allocator, wide[0..len]);
}

const LiveDisplayInfo = struct {
	hardware_id: []const u8,
	width: u32 = 0,
	height: u32 = 0,
	refresh_hz: u32 = 0,
	primary: bool = false,
};

/// Win32_DesktopMonitor's ScreenWidth/ScreenHeight are almost always blank, this is the reliable way to get a monitor's actual current resolution and refresh rate, but it's a live display driver query, not WMI, so it's kept separate from the EDID data above and matched up afterward by hardware ID.
fn enumerateLiveDisplays(allocator: std.mem.Allocator) ![]LiveDisplayInfo {
	var result = std.ArrayList(LiveDisplayInfo).empty;
	var adapter_index: win32.DWORD = 0;
	while (true) : (adapter_index += 1) {
		var adapter: win32.DISPLAY_DEVICEW = std.mem.zeroes(win32.DISPLAY_DEVICEW);
		adapter.cb = @sizeOf(win32.DISPLAY_DEVICEW);
		if (win32.EnumDisplayDevicesW(null, adapter_index, &adapter, 0) == 0) break;
		if (adapter.StateFlags & win32.DISPLAY_DEVICE_ATTACHED_TO_DESKTOP == 0) continue;
		var monitor: win32.DISPLAY_DEVICEW = std.mem.zeroes(win32.DISPLAY_DEVICEW);
		monitor.cb = @sizeOf(win32.DISPLAY_DEVICEW);
		if (win32.EnumDisplayDevicesW(@ptrCast(&adapter.DeviceName), 0, &monitor, 0) == 0) continue;
		var mode: win32.DEVMODEW = std.mem.zeroes(win32.DEVMODEW);
		mode.dmSize = @sizeOf(win32.DEVMODEW);
		if (win32.EnumDisplaySettingsW(@ptrCast(&adapter.DeviceName), win32.ENUM_CURRENT_SETTINGS, &mode) == 0) continue;
		try result.append(allocator, .{
			.hardware_id = extractHardwareId(try wideToUtf8(allocator, @ptrCast(&monitor.DeviceID))),
			.width = mode.dmPelsWidth,
			.height = mode.dmPelsHeight,
			.refresh_hz = mode.dmDisplayFrequency,
			.primary = adapter.StateFlags & win32.DISPLAY_DEVICE_PRIMARY_DEVICE != 0,
		});
	}
	return result.toOwnedSlice(allocator);
}

/// VideoInputType on WmiMonitorBasicDisplayParams is the EDID basic display parameters input flag: 0 = analog (VGA), 1 = digital (DVI/HDMI/DisplayPort/eDP etc).
fn decodeVideoInputType(raw: []const u8) []const u8 {
	if (std.mem.eql(u8, raw, "0")) return "Analog";
	if (std.mem.eql(u8, raw, "1")) return "Digital";
	return "";
}

/// Win32_DesktopMonitor (ROOT\CIMV2) is almost always sparse on modern hardware (blank manufacturer, blank resolution). WmiMonitorID/WmiMonitorBasicDisplayParams (ROOT\WMI, exposed by the monitor class driver from the panel's own EDID) give real identity and physical size instead, EnumDisplayDevices/EnumDisplaySettings (native Win32, no WMI involved) give the actual live resolution and refresh rate.
pub fn getItems(allocator: std.mem.Allocator) ![]CategoryItem {
	const conn = try wmi.WmiConnection.instance(std.heap.page_allocator);
	const id_rows = try conn.query(allocator, "SELECT InstanceName, UserFriendlyName, ManufacturerName, SerialNumberID, WeekOfManufacture, YearOfManufacture FROM WmiMonitorID", "ROOT\\WMI");
	defer for (id_rows) |*row| row.deinit();
	const size_rows = conn.query(allocator, "SELECT InstanceName, MaxHorizontalImageSize, MaxVerticalImageSize, VideoInputType FROM WmiMonitorBasicDisplayParams", "ROOT\\WMI") catch &.{};
	defer for (size_rows) |*row| row.deinit();
	const live_displays = try enumerateLiveDisplays(allocator);
	var items = std.ArrayList(CategoryItem).empty;
	for (id_rows) |*row| {
		const friendly_name = try decodeEdidString(allocator, try row.getList(allocator, "UserFriendlyName"));
		const label = if (friendly_name.len == 0) "Display" else try std.mem.concat(allocator, u8, &.{ "Display, ", friendly_name });
		var properties = std.ArrayList(PropertyRow).empty;
		try properties.append(allocator, .{ .name = "Manufacturer", .value = try decodeEdidString(allocator, try row.getList(allocator, "ManufacturerName")) });
		const instance_name = try row.get(allocator, "InstanceName");
		const hardware_id = extractHardwareId(instance_name);
		if (hardware_id.len > 0) {
			for (live_displays) |live| {
				if (!std.mem.eql(u8, live.hardware_id, hardware_id)) continue;
				try properties.append(allocator, .{ .name = "Resolution", .value = try std.fmt.allocPrint(allocator, "{d} x {d}", .{ live.width, live.height }) });
				if (live.refresh_hz > 1) try properties.append(allocator, .{ .name = "Refresh Rate", .value = try format.withUnit(allocator, try std.fmt.allocPrint(allocator, "{d}", .{live.refresh_hz}), " Hz") });
				try properties.append(allocator, .{ .name = "Primary Display", .value = if (live.primary) "Yes" else "No" });
				break;
			}
		}
		const serial = try decodeEdidString(allocator, try row.getList(allocator, "SerialNumberID"));
		if (!std.mem.eql(u8, serial, "0")) try properties.append(allocator, .{ .name = "Serial Number", .value = serial });
		const week = try row.get(allocator, "WeekOfManufacture");
		const year = try row.get(allocator, "YearOfManufacture");
		if (week.len > 0 and year.len > 0 and !std.mem.eql(u8, week, "0") and !std.mem.eql(u8, week, "255")) try properties.append(allocator, .{ .name = "Manufacture Date", .value = try std.fmt.allocPrint(allocator, "Week {s}, {s}", .{ week, year }) });
		for (size_rows) |*size_row| {
			const size_instance = try size_row.get(allocator, "InstanceName");
			if (!std.mem.eql(u8, size_instance, instance_name)) continue;
			const size = try screenSizeInches(allocator, try size_row.get(allocator, "MaxHorizontalImageSize"), try size_row.get(allocator, "MaxVerticalImageSize"));
			if (size.len > 0) try properties.append(allocator, .{ .name = "Screen Size", .value = size });
			try properties.append(allocator, .{ .name = "Input Type", .value = decodeVideoInputType(try size_row.get(allocator, "VideoInputType")) });
			break;
		}
		try items.append(allocator, .{ .label = label, .properties = try properties.toOwnedSlice(allocator) });
	}
	return items.toOwnedSlice(allocator);
}
