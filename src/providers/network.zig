const std = @import("std");
const wmi = @import("../wmi.zig");
const category_item = @import("../core/category_item.zig");
const CategoryItem = category_item.CategoryItem;
const PropertyRow = category_item.PropertyRow;

/// Link local unicast addresses are defined by the fe80::/10 prefix (RFC 4291), a purely syntactic check, not a WMI provided flag.
fn isLinkLocalIpv6(address: []const u8) bool {
	return address.len >= 5 and std.ascii.eqlIgnoreCase(address[0..5], "fe80:");
}

/// SuffixOrigin = 5 (Random) marks an RFC 4941 privacy address, the same flag ipconfig uses to label "Temporary IPv6 Address". That flag only exists on the newer MSFT_NetIPAddress class (ROOT\StandardCimv2), not Win32_NetworkAdapterConfiguration, hence the separate query. Falls back to an empty set if that class isn't available (pre Windows 8).
fn temporaryIpv6Addresses(allocator: std.mem.Allocator, conn: *wmi.WmiConnection) !std.StringHashMap(void) {
	var result = std.StringHashMap(void).init(allocator);
	const rows = conn.query(allocator, "SELECT IPAddress FROM MSFT_NetIPAddress WHERE AddressFamily = 23 AND SuffixOrigin = 5", "ROOT\\StandardCimv2") catch return result;
	defer for (rows) |*row| row.deinit();
	for (rows) |*row| try result.put(try row.get(allocator, "IPAddress"), {});
	return result;
}

fn appendAddresses(allocator: std.mem.Allocator, properties: *std.ArrayList(PropertyRow), name: []const u8, addresses: []const []const u8) !void {
	for (addresses, 0..) |address, i| {
		const label = if (addresses.len > 1) try std.fmt.allocPrint(allocator, "{s} {d}", .{ name, i + 1 }) else name;
		try properties.append(allocator, .{ .name = label, .value = address });
	}
}

pub fn getItems(allocator: std.mem.Allocator) ![]CategoryItem {
	const conn = try wmi.WmiConnection.instance(std.heap.page_allocator);
	var temp_addresses = try temporaryIpv6Addresses(allocator, conn);
	const rows = try conn.query(allocator, "SELECT Description, MACAddress, IPAddress, IPSubnet, DefaultIPGateway, DNSServerSearchOrder, DNSDomain, DHCPEnabled FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled = TRUE", "ROOT\\CIMV2");
	defer for (rows) |*row| row.deinit();
	var items = std.ArrayList(CategoryItem).empty;
	for (rows) |*row| {
		const label = try std.mem.concat(allocator, u8, &.{ "Network, ", try row.get(allocator, "Description") });
		var properties = std.ArrayList(PropertyRow).empty;
		try properties.append(allocator, .{ .name = "MAC Address", .value = try row.get(allocator, "MACAddress") });
		var ipv4 = std.ArrayList([]const u8).empty;
		var ipv6 = std.ArrayList([]const u8).empty;
		var ipv6_temporary = std.ArrayList([]const u8).empty;
		var ipv6_link_local = std.ArrayList([]const u8).empty;
		for (try row.getList(allocator, "IPAddress")) |address| {
			if (std.mem.indexOfScalar(u8, address, ':') == null) try ipv4.append(allocator, address) else if (isLinkLocalIpv6(address)) try ipv6_link_local.append(allocator, address) else if (temp_addresses.contains(address)) try ipv6_temporary.append(allocator, address) else try ipv6.append(allocator, address);
		}
		try appendAddresses(allocator, &properties, "IPv4 Address", ipv4.items);
		try appendAddresses(allocator, &properties, "IPv6 Address", ipv6.items);
		try appendAddresses(allocator, &properties, "Temporary IPv6 Address", ipv6_temporary.items);
		try appendAddresses(allocator, &properties, "Link-local IPv6 Address", ipv6_link_local.items);
		try properties.append(allocator, .{ .name = "Subnet Mask", .value = try row.get(allocator, "IPSubnet") });
		try properties.append(allocator, .{ .name = "Default Gateway", .value = try row.get(allocator, "DefaultIPGateway") });
		try properties.append(allocator, .{ .name = "DNS Servers", .value = try row.get(allocator, "DNSServerSearchOrder") });
		try properties.append(allocator, .{ .name = "DNS Suffix", .value = try row.get(allocator, "DNSDomain") });
		try properties.append(allocator, .{ .name = "DHCP Enabled", .value = try row.get(allocator, "DHCPEnabled") });
		try items.append(allocator, .{ .label = label, .properties = try properties.toOwnedSlice(allocator) });
	}
	return items.toOwnedSlice(allocator);
}
