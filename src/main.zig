const std = @import("std");
const win32 = @import("win32.zig");
const main_window = @import("main_window.zig");

pub fn main() !void {
	const instance = win32.GetModuleHandleW(null);
	var window = main_window.MainWindow.init(instance, std.heap.page_allocator);
	const hwnd = try window.create();
	if (hwnd == null) return;
	// nCmdShow isn't reachable from a plain main() the way WinMain gets it, SW_SHOWDEFAULT is a reasonable fixed stand in.
	_ = win32.ShowWindow(hwnd, win32.SW_SHOWDEFAULT);
	_ = win32.UpdateWindow(hwnd);
	var msg: win32.MSG = undefined;
	while (win32.GetMessageW(&msg, null, 0, 0) != 0) {
		if (win32.TranslateAcceleratorW(hwnd, window.accelerators, &msg) != 0) continue;
		if (win32.IsDialogMessageW(hwnd, &msg) != 0) continue;
		_ = win32.TranslateMessage(&msg);
		_ = win32.DispatchMessageW(&msg);
	}
}
