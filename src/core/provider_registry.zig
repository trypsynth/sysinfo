const std = @import("std");
const CategoryItem = @import("category_item.zig").CategoryItem;
const battery = @import("../providers/battery.zig");
const bios = @import("../providers/bios.zig");
const computer_system = @import("../providers/computer_system.zig");
const cpu = @import("../providers/cpu.zig");
const display = @import("../providers/display.zig");
const gpu = @import("../providers/gpu.zig");
const memory = @import("../providers/memory.zig");
const motherboard = @import("../providers/motherboard.zig");
const network = @import("../providers/network.zig");
const os_provider = @import("../providers/os.zig");
const storage = @import("../providers/storage.zig");

pub const GetItemsFn = *const fn (allocator: std.mem.Allocator) anyerror![]CategoryItem;

pub const ProviderInfo = struct {
	get_items: GetItemsFn,
	// Same shape as get_items, but returns its category label(s) immediately with every property value set to "Loading...". Static single-instance providers (BIOS, Processor, etc.) build this with no query at all; providers whose instance count actually varies (Network, Storage, etc.) run one cheap identity-only query to learn real labels before the full, slower query runs.
	get_shapes: GetItemsFn,
};

pub const providers = [_]ProviderInfo{
	.{ .get_items = battery.getItems, .get_shapes = battery.getShapes },
	.{ .get_items = bios.getItems, .get_shapes = bios.getShapes },
	.{ .get_items = computer_system.getItems, .get_shapes = computer_system.getShapes },
	.{ .get_items = cpu.getItems, .get_shapes = cpu.getShapes },
	.{ .get_items = display.getItems, .get_shapes = display.getShapes },
	.{ .get_items = gpu.getItems, .get_shapes = gpu.getShapes },
	.{ .get_items = memory.getItems, .get_shapes = memory.getShapes },
	.{ .get_items = motherboard.getItems, .get_shapes = motherboard.getShapes },
	.{ .get_items = network.getItems, .get_shapes = network.getShapes },
	.{ .get_items = os_provider.getItems, .get_shapes = os_provider.getShapes },
	.{ .get_items = storage.getItems, .get_shapes = storage.getShapes },
};
