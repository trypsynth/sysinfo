const std = @import("std");

fn pluralize(allocator: std.mem.Allocator, count: u64, singular: []const u8) ![]u8 {
	return std.fmt.allocPrint(allocator, "{d} {s}{s}", .{ count, singular, if (count == 1) "" else "s" });
}

fn joinWithAnd(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
	if (parts.len == 1) return allocator.dupe(u8, parts[0]);
	if (parts.len == 2) return std.mem.concat(allocator, u8, &.{ parts[0], " and ", parts[1] });
	var result = std.ArrayList(u8).empty;
	for (parts, 0..) |part, i| {
		if (i > 0) try result.appendSlice(allocator, if (i + 1 == parts.len) ", and " else ", ");
		try result.appendSlice(allocator, part);
	}
	return result.toOwnedSlice(allocator);
}

/// Parses a decimal byte count string and renders it with the best fitting unit, e.g. "11.52 GB" or "2.31 TB". Returns the input unchanged if it isn't a parseable number.
pub fn formatBytes(allocator: std.mem.Allocator, bytes_str: []const u8) ![]u8 {
	if (bytes_str.len == 0) return allocator.dupe(u8, bytes_str);
	const bytes = std.fmt.parseUnsigned(u64, bytes_str, 10) catch return allocator.dupe(u8, bytes_str);
	const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB", "PB" };
	var value: f64 = @floatFromInt(bytes);
	var unit_index: usize = 0;
	while (value >= 1024.0 and unit_index < 5) : (unit_index += 1) value /= 1024.0;
	return std.fmt.allocPrint(allocator, "{d:.2} {s}", .{ value, units[unit_index] });
}

/// Appends suffix to value, e.g. withUnit("4800", " MHz") produces "4800 MHz". Returns "" unchanged if value is empty, so a missing property still gets filtered out instead of showing a bare unit.
pub fn withUnit(allocator: std.mem.Allocator, value: []const u8, suffix: []const u8) ![]u8 {
	if (value.len == 0) return allocator.dupe(u8, value);
	return std.mem.concat(allocator, u8, &.{ value, suffix });
}

/// Formats part as a percentage of whole with two decimal places, e.g. formatPercent(561, 930) produces "60.32%". Returns "" if whole is zero or negative.
pub fn formatPercent(allocator: std.mem.Allocator, part: f64, whole: f64) ![]u8 {
	if (whole <= 0.0) return allocator.dupe(u8, "");
	return std.fmt.allocPrint(allocator, "{d:.2}%", .{(part / whole) * 100.0});
}

/// Formats a duration for reading aloud, e.g. "1 hour and 2 minutes" or "1 hour, 2 minutes, and 3 seconds". Zero value leading units are omitted (no "0 days"), always produces at least one component.
pub fn formatDuration(allocator: std.mem.Allocator, total_seconds: u64) ![]u8 {
	const days = total_seconds / 86400;
	const hours = (total_seconds % 86400) / 3600;
	const minutes = (total_seconds % 3600) / 60;
	const seconds = total_seconds % 60;
	var parts = std.ArrayList([]const u8).empty;
	if (days > 0) try parts.append(allocator, try pluralize(allocator, days, "day"));
	if (hours > 0) try parts.append(allocator, try pluralize(allocator, hours, "hour"));
	if (minutes > 0) try parts.append(allocator, try pluralize(allocator, minutes, "minute"));
	if (seconds > 0 or parts.items.len == 0) try parts.append(allocator, try pluralize(allocator, seconds, "second"));
	return joinWithAnd(allocator, parts.items);
}
