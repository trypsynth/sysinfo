pub const PropertyRow = struct {
	name: []const u8,
	value: []const u8,
};

pub const CategoryItem = struct {
	label: []const u8,
	properties: []const PropertyRow,
};
