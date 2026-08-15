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

pub const providers = [_]GetItemsFn{
	battery.getItems,
	bios.getItems,
	computer_system.getItems,
	cpu.getItems,
	display.getItems,
	gpu.getItems,
	memory.getItems,
	motherboard.getItems,
	network.getItems,
	os_provider.getItems,
	storage.getItems,
};
