const std = @import("std");
const win32 = @import("win32.zig");
const provider_registry = @import("core/provider_registry.zig");
const category_item = @import("core/category_item.zig");
const CategoryItem = category_item.CategoryItem;
const PropertyRow = category_item.PropertyRow;

const categories_label_id: usize = 101;
const categories_list_id: usize = 102;
const properties_label_id: usize = 103;
const properties_list_id: usize = 104;
const menu_refresh_id: usize = 201;
const menu_exit_id: usize = 202;
const menu_copy_id: usize = 203;
const refresh_timer_id: usize = 301;
const refresh_tick_ms: win32.UINT = 100;

fn idMenu(id: usize) win32.HMENU {
	return @ptrFromInt(id);
}

fn ptrToLparam(ptr: anytype) win32.LPARAM {
	return @bitCast(@intFromPtr(ptr));
}

fn lparamToPtr(comptime T: type, lparam: win32.LPARAM) T {
	return @ptrFromInt(@as(usize, @bitCast(lparam)));
}

fn toWide(allocator: std.mem.Allocator, s: []const u8) ![:0]u16 {
	return std.unicode.utf8ToUtf16LeAllocZ(allocator, s);
}

/// Builds a minimal in memory DLGTEMPLATE with zero template defined items, every control is created by hand in onInitDialog. Using the predefined dialog class (windowClass = 0) is what gets us free accessible name association between each STATIC label and the control after it, plus Tab key navigation via IsDialogMessage, neither works for a plain CreateWindowEx window. Only the outer size is approximate here, create() overrides it in real pixels via SetWindowPos right after creation.
fn buildDialogTemplate(allocator: std.mem.Allocator, title: [:0]const u16) ![]u8 {
	var buffer = std.ArrayList(u8).empty;
	const style: u32 = win32.WS_POPUP | win32.WS_CAPTION | win32.WS_SYSMENU | win32.WS_THICKFRAME | win32.WS_MINIMIZEBOX | win32.WS_MAXIMIZEBOX | win32.WS_CLIPCHILDREN | win32.DS_SETFONT;
	try buffer.appendSlice(allocator, std.mem.asBytes(&style));
	try buffer.appendSlice(allocator, std.mem.asBytes(&@as(u32, 0)));
	try buffer.appendSlice(allocator, std.mem.asBytes(&@as(u16, 0)));
	try buffer.appendSlice(allocator, std.mem.asBytes(&@as(u16, 0)));
	try buffer.appendSlice(allocator, std.mem.asBytes(&@as(u16, 0)));
	try buffer.appendSlice(allocator, std.mem.asBytes(&@as(u16, 300)));
	try buffer.appendSlice(allocator, std.mem.asBytes(&@as(u16, 200)));
	try buffer.appendSlice(allocator, std.mem.asBytes(&@as(u16, 0)));
	try buffer.appendSlice(allocator, std.mem.asBytes(&@as(u16, 0)));
	try buffer.appendSlice(allocator, std.mem.sliceAsBytes(title[0 .. title.len + 1]));
	try buffer.appendSlice(allocator, std.mem.asBytes(&@as(u16, 8)));
	const font_name = std.unicode.utf8ToUtf16LeStringLiteral("MS Shell Dlg");
	try buffer.appendSlice(allocator, std.mem.sliceAsBytes(font_name[0 .. font_name.len + 1]));
	return buffer.toOwnedSlice(allocator);
}

const provider_count = provider_registry.providers.len;

const ProviderResult = struct {
	items: []CategoryItem = &.{},
};

// Shared by every not-yet-finished provider's placeholder category, a single static allocation reused as-is across every rebuild rather than re-created each time. Reusing the exact same slice (compared by .ptr in rebuildCategoriesFromCompleted) is what lets a placeholder that's still loading be told apart from one that just started real work, without one being mistaken for "changed" just because some *other* provider finished in the meantime.
const loading_properties = [_]PropertyRow{.{ .name = "Status", .value = "Loading..." }};

/// Runs on its own worker thread, one per provider (see startRefresh), so a provider stuck waiting on a slow or first-time-spun-up WMI namespace no longer blocks every other provider behind it, or the window from appearing at all. Errors are swallowed the same way the old sequential loop's `catch continue` did, just per provider now instead of process wide. `done` is set last, with a release store, so onTimerTick's acquire load on the UI thread is guaranteed to see `out.items` fully written by the time it observes `done == true`.
fn runProviderThread(get_items: provider_registry.GetItemsFn, allocator: std.mem.Allocator, out: *ProviderResult, done: *bool) void {
	out.items = get_items(allocator) catch &.{};
	@atomicStore(bool, done, true, .release);
}

pub const MainWindow = struct {
	instance: win32.HINSTANCE,
	hwnd: win32.HWND = null,
	categories_label: win32.HWND = null,
	categories_list: win32.HWND = null,
	properties_label: win32.HWND = null,
	properties_list: win32.HWND = null,
	accelerators: win32.HACCEL = null,
	items: []const CategoryItem = &.{},
	arena: std.heap.ArenaAllocator,
	// One dedicated arena per provider, each ever touched only by that provider's own worker thread, so no locking is needed. self.items (built in the combine arena above) borrows from these, so they're reset together with it at the start of every refresh, never independently.
	provider_arenas: [provider_count]std.heap.ArenaAllocator = undefined,
	results: [provider_count]ProviderResult = undefined,
	provider_done: [provider_count]bool = undefined,
	threads: [provider_count]?std.Thread = undefined,
	// How many providers were done as of the last rebuild, so onTimerTick only touches the listbox when something has actually changed, not on every idle tick. Starts higher than provider_count could ever be so the very first tick (0 done) still counts as "changed" and paints the initial all-placeholders list.
	last_done_count: usize = provider_count + 1,
	refresh_timer_active: bool = false,
	// The properties slice currently painted into properties_list, compared by .ptr against the selected category's properties each rebuild so the pane is only ever repainted (losing scroll position) when what it's showing actually changed, not just because some other category finished loading.
	rendered_properties: []const PropertyRow = &.{},

	pub fn init(instance: win32.HINSTANCE, backing_allocator: std.mem.Allocator) MainWindow {
		var self: MainWindow = .{ .instance = instance, .arena = std.heap.ArenaAllocator.init(backing_allocator) };
		for (&self.provider_arenas) |*provider_arena| provider_arena.* = std.heap.ArenaAllocator.init(backing_allocator);
		for (&self.results) |*result| result.* = .{};
		for (&self.provider_done) |*done| done.* = false;
		for (&self.threads) |*t| t.* = null;
		return self;
	}

	pub fn create(self: *MainWindow) !win32.HWND {
		const template = try buildDialogTemplate(std.heap.page_allocator, std.unicode.utf8ToUtf16LeStringLiteral("System Information"));
		defer std.heap.page_allocator.free(template);
		self.hwnd = win32.CreateDialogIndirectParamW(self.instance, template.ptr, null, dialogProc, ptrToLparam(self));
		if (self.hwnd != null) {
			const width: i32 = 900;
			const height: i32 = 600;
			const screen_width = win32.GetSystemMetrics(win32.SM_CXSCREEN);
			const screen_height = win32.GetSystemMetrics(win32.SM_CYSCREEN);
			_ = win32.SetWindowPos(self.hwnd, null, @divTrunc(screen_width - width, 2), @divTrunc(screen_height - height, 2), width, height, win32.SWP_NOZORDER);
		}
		return self.hwnd;
	}

	fn dialogProc(hwnd: win32.HWND, msg: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM) callconv(.c) win32.INT_PTR {
		var self: ?*MainWindow = null;
		if (msg == win32.WM_INITDIALOG) {
			self = lparamToPtr(*MainWindow, lparam);
			_ = win32.SetWindowLongPtrW(hwnd, win32.GWLP_USERDATA, @bitCast(@intFromPtr(self.?)));
			self.?.hwnd = hwnd;
		} else {
			const raw = win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA);
			if (raw != 0) self = @ptrFromInt(@as(usize, @bitCast(raw)));
		}
		if (self) |s| return s.handleMessage(hwnd, msg, wparam, lparam);
		return 0;
	}

	fn handleMessage(self: *MainWindow, hwnd: win32.HWND, msg: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM) win32.INT_PTR {
		switch (msg) {
			win32.WM_INITDIALOG => {
				self.onInitDialog(hwnd);
				return 1;
			},
			win32.WM_SIZE => {
				self.onSize(win32.loword(lparam), win32.hiword(lparam));
				return 1;
			},
			win32.WM_COMMAND => {
				self.onCommand(wparam, lparam);
				return 1;
			},
			win32.WM_TIMER => {
				self.onTimerTick();
				return 1;
			},
			win32.WM_CLOSE => {
				_ = win32.DestroyWindow(hwnd);
				return 1;
			},
			win32.WM_DESTROY => {
				// Guards against a worker thread from an in-flight refresh writing into self.results/self.provider_arenas after this MainWindow (a stack local in main()) has gone out of scope. Providers are quick enough in practice that this is rarely more than an instant, worst case bounded by however long the single slowest provider takes.
				self.waitForOutstandingThreads();
				win32.PostQuitMessage(0);
				return 1;
			},
			else => return 0,
		}
	}

	fn onInitDialog(self: *MainWindow, hwnd: win32.HWND) void {
		const font = win32.GetStockObject(win32.DEFAULT_GUI_FONT);
		self.categories_label = win32.CreateWindowExW(0, std.unicode.utf8ToUtf16LeStringLiteral("STATIC"), std.unicode.utf8ToUtf16LeStringLiteral("Categories"), win32.WS_CHILD | win32.WS_VISIBLE | win32.WS_GROUP, 0, 0, 0, 0, hwnd, idMenu(categories_label_id), self.instance, null);
		self.categories_list = win32.CreateWindowExW(win32.WS_EX_CLIENTEDGE, std.unicode.utf8ToUtf16LeStringLiteral("LISTBOX"), null, win32.WS_CHILD | win32.WS_VISIBLE | win32.WS_VSCROLL | win32.WS_TABSTOP | win32.LBS_NOTIFY | win32.LBS_HASSTRINGS, 0, 0, 0, 0, hwnd, idMenu(categories_list_id), self.instance, null);
		self.properties_label = win32.CreateWindowExW(0, std.unicode.utf8ToUtf16LeStringLiteral("STATIC"), std.unicode.utf8ToUtf16LeStringLiteral("Properties"), win32.WS_CHILD | win32.WS_VISIBLE | win32.WS_GROUP, 0, 0, 0, 0, hwnd, idMenu(properties_label_id), self.instance, null);
		self.properties_list = win32.CreateWindowExW(win32.WS_EX_CLIENTEDGE, std.unicode.utf8ToUtf16LeStringLiteral("LISTBOX"), null, win32.WS_CHILD | win32.WS_VISIBLE | win32.WS_VSCROLL | win32.WS_TABSTOP | win32.LBS_NOTIFY | win32.LBS_HASSTRINGS, 0, 0, 0, 0, hwnd, idMenu(properties_list_id), self.instance, null);
		for ([_]win32.HWND{ self.categories_label, self.categories_list, self.properties_label, self.properties_list }) |control| _ = win32.SendMessageW(control, win32.WM_SETFONT, @intFromPtr(font), 1);
		const file_menu = win32.CreatePopupMenu();
		_ = win32.AppendMenuW(file_menu, win32.MF_STRING, menu_refresh_id, std.unicode.utf8ToUtf16LeStringLiteral("&Refresh\tF5"));
		_ = win32.AppendMenuW(file_menu, win32.MF_SEPARATOR, 0, null);
		_ = win32.AppendMenuW(file_menu, win32.MF_STRING, menu_exit_id, std.unicode.utf8ToUtf16LeStringLiteral("E&xit"));
		const edit_menu = win32.CreatePopupMenu();
		_ = win32.AppendMenuW(edit_menu, win32.MF_STRING, menu_copy_id, std.unicode.utf8ToUtf16LeStringLiteral("&Copy\tCtrl+C"));
		const menu_bar = win32.CreateMenu();
		_ = win32.AppendMenuW(menu_bar, win32.MF_POPUP, @intFromPtr(file_menu), std.unicode.utf8ToUtf16LeStringLiteral("&File"));
		_ = win32.AppendMenuW(menu_bar, win32.MF_POPUP, @intFromPtr(edit_menu), std.unicode.utf8ToUtf16LeStringLiteral("&Edit"));
		_ = win32.SetMenu(hwnd, menu_bar);
		const accels = [_]win32.ACCEL{ .{ .fVirt = win32.FVIRTKEY, .key = win32.VK_F5, .cmd = menu_refresh_id }, .{ .fVirt = win32.FVIRTKEY | win32.FCONTROL, .key = 'C', .cmd = menu_copy_id } };
		self.accelerators = win32.CreateAcceleratorTableW(&accels, accels.len);
		self.startRefresh();
		_ = win32.SetFocus(self.categories_list);
	}

	fn onSize(self: *MainWindow, width: u16, height: u16) void {
		if (self.categories_list == null) return;
		const margin: i32 = 10;
		const label_height: i32 = 18;
		const half_width = @divTrunc(@as(i32, width) - margin * 3, 2);
		const list_top = margin + label_height;
		const list_height = @as(i32, height) - list_top - margin;
		const right_x = margin * 2 + half_width;
		_ = win32.MoveWindow(self.categories_label, margin, margin, half_width, label_height, 1);
		_ = win32.MoveWindow(self.categories_list, margin, list_top, half_width, list_height, 1);
		_ = win32.MoveWindow(self.properties_label, right_x, margin, half_width, label_height, 1);
		_ = win32.MoveWindow(self.properties_list, right_x, list_top, half_width, list_height, 1);
	}

	fn onCommand(self: *MainWindow, wparam: win32.WPARAM, lparam: win32.LPARAM) void {
		const id = wparam & 0xffff;
		if (lparam != 0) {
			if (id == categories_list_id and (wparam >> 16) == win32.LBN_SELCHANGE) {
				const index: i32 = @intCast(@as(isize, @bitCast(win32.SendMessageW(self.categories_list, win32.LB_GETCURSEL, 0, 0))));
				self.populateProperties(index);
				// Keep rendered_properties in sync with a manual click too, so a background rebuild right afterward correctly recognizes this category as already showing its current content instead of needlessly repainting it.
				self.rendered_properties = if (index >= 0 and index < self.items.len) self.items[@intCast(index)].properties else &.{};
			}
			return;
		}
		if (id == menu_refresh_id) {
			self.startRefresh();
		} else if (id == menu_exit_id) {
			_ = win32.DestroyWindow(self.hwnd);
		} else if (id == menu_copy_id) {
			self.copySelectedProperty();
		} else if (id == @as(usize, @intCast(win32.IDCANCEL))) {
			_ = win32.DestroyWindow(self.hwnd);
		}
	}

	/// Kicks off a fresh load. Every provider runs on its own worker thread (runProviderThread) instead of being awaited here, so the window shows up immediately and a single slow provider (e.g. a WMI namespace whose provider host has to spin up for the first time) can't hold up either the window or every other provider behind it. A repeating timer (onTimerTick) picks up results as they land.
	fn startRefresh(self: *MainWindow) void {
		if (self.refresh_timer_active) return; // a refresh is already in flight; let it finish rather than racing a second set of threads against the first over shared state
		_ = win32.SendMessageW(self.categories_list, win32.LB_RESETCONTENT, 0, 0);
		_ = win32.SendMessageW(self.properties_list, win32.LB_RESETCONTENT, 0, 0);
		_ = self.arena.reset(.retain_capacity);
		self.items = &.{};
		self.last_done_count = provider_count + 1; // never equal to a real done_count, so the first tick's all-placeholders state still counts as "changed" and gets painted
		self.rendered_properties = &.{};
		for (&self.results) |*result| result.* = .{};
		for (&self.provider_done) |*done| done.* = false;
		for (provider_registry.providers, 0..) |get_items, i| {
			_ = self.provider_arenas[i].reset(.retain_capacity);
			const provider_allocator = self.provider_arenas[i].allocator();
			// If the thread pool is exhausted (very unlikely for 11 short-lived threads), fall back to running that one provider inline rather than dropping it.
			self.threads[i] = std.Thread.spawn(.{}, runProviderThread, .{ get_items, provider_allocator, &self.results[i], &self.provider_done[i] }) catch blk: {
				runProviderThread(get_items, provider_allocator, &self.results[i], &self.provider_done[i]);
				break :blk null;
			};
		}
		self.refresh_timer_active = true;
		_ = win32.SetTimer(self.hwnd, refresh_timer_id, refresh_tick_ms, null);
		self.onTimerTick(); // pick up anything that already finished (e.g. the inline fallback above) instead of waiting for the first tick
	}

	fn onTimerTick(self: *MainWindow) void {
		var done_count: usize = 0;
		for (&self.provider_done) |*done| {
			if (@atomicLoad(bool, done, .acquire)) done_count += 1;
		}
		if (done_count != self.last_done_count) {
			self.last_done_count = done_count;
			self.rebuildCategoriesFromCompleted();
		}
		if (done_count == provider_count) {
			_ = win32.KillTimer(self.hwnd, refresh_timer_id);
			self.refresh_timer_active = false;
			self.waitForOutstandingThreads(); // every provider is done, so this just reclaims the OS thread handles
		}
	}

	/// Rebuilds the categories list from whichever providers have completed so far, standing in a placeholder category (loading_properties) for every provider that hasn't finished yet so the full set of categories is visible from the very first paint rather than trickling in one at a time. Only called when the completed count has actually changed (see onTimerTick), so the list doesn't flicker while a slow provider is still pending and nothing else has changed.
	fn rebuildCategoriesFromCompleted(self: *MainWindow) void {
		const allocator = self.arena.allocator();
		var collected = std.ArrayList(CategoryItem).empty;
		for (0..provider_count) |i| {
			if (@atomicLoad(bool, &self.provider_done[i], .acquire)) {
				collected.appendSlice(allocator, self.results[i].items) catch continue;
			} else {
				collected.append(allocator, .{ .label = provider_registry.placeholder_labels[i], .properties = &loading_properties }) catch continue;
			}
		}
		std.mem.sort(CategoryItem, collected.items, {}, struct {
			fn lessThan(_: void, a: CategoryItem, b: CategoryItem) bool {
				return std.mem.lessThan(u8, a.label, b.label);
			}
		}.lessThan);
		// Preserve whatever the user has selected across the rebuild (matched by label, since indices shift as more categories land), rather than yanking their selection back to a fixed spot every time another provider finishes.
		const old_index: i32 = @intCast(@as(isize, @bitCast(win32.SendMessageW(self.categories_list, win32.LB_GETCURSEL, 0, 0))));
		const selected_label: ?[]const u8 = if (old_index < 0 or old_index >= self.items.len) null else self.items[@intCast(old_index)].label;
		_ = win32.SendMessageW(self.categories_list, win32.LB_RESETCONTENT, 0, 0);
		self.items = collected.items;
		for (self.items) |item| {
			const wide = toWide(allocator, item.label) catch continue;
			_ = win32.SendMessageW(self.categories_list, win32.LB_ADDSTRING, 0, ptrToLparam(wide.ptr));
		}
		if (self.items.len == 0) return;
		var selected_index: usize = 0;
		var matched_by_label = false;
		if (selected_label) |label| {
			for (self.items, 0..) |item, i| {
				if (std.mem.eql(u8, item.label, label)) {
					selected_index = i;
					matched_by_label = true;
					break;
				}
			}
		}
		// A label can genuinely disappear between rebuilds (e.g. the "Memory" placeholder splitting into "Memory, Summary" plus one entry per stick once that provider finishes). Falling back to the same position, rather than jumping back to the first category, keeps the user roughly where they were.
		if (!matched_by_label and old_index >= 0) selected_index = @min(@as(usize, @intCast(old_index)), self.items.len - 1);
		_ = win32.SendMessageW(self.categories_list, win32.LB_SETCURSEL, selected_index, 0);
		// Only actually repaint the properties pane (which resets scroll position) when what it would show has changed: the selection moved to a genuinely different category, or the same category's content changed (e.g. its placeholder just got replaced with real data). A provider finishing in the background while the user looks at an already-loaded, unrelated category should never touch this.
		const new_properties = self.items[selected_index].properties;
		if (!matched_by_label or new_properties.ptr != self.rendered_properties.ptr) {
			self.populateProperties(@intCast(selected_index));
			self.rendered_properties = new_properties;
		}
	}

	fn waitForOutstandingThreads(self: *MainWindow) void {
		for (&self.threads) |*maybe_thread| {
			if (maybe_thread.*) |t| {
				t.join();
				maybe_thread.* = null;
			}
		}
	}

	fn populateProperties(self: *MainWindow, category_index: i32) void {
		_ = win32.SendMessageW(self.properties_list, win32.LB_RESETCONTENT, 0, 0);
		if (category_index < 0 or category_index >= self.items.len) return;
		const allocator = self.arena.allocator();
		for (self.items[@intCast(category_index)].properties) |prop| {
			if (prop.value.len == 0) continue;
			const line = std.mem.concat(allocator, u8, &.{ prop.name, ": ", prop.value }) catch continue;
			const wide = toWide(allocator, line) catch continue;
			_ = win32.SendMessageW(self.properties_list, win32.LB_ADDSTRING, 0, ptrToLparam(wide.ptr));
		}
		if (win32.SendMessageW(self.properties_list, win32.LB_GETCOUNT, 0, 0) > 0) _ = win32.SendMessageW(self.properties_list, win32.LB_SETCURSEL, 0, 0);
	}

	fn copySelectedProperty(self: *MainWindow) void {
		if (win32.GetFocus() != self.properties_list) return;
		const index: i32 = @intCast(@as(isize, @bitCast(win32.SendMessageW(self.properties_list, win32.LB_GETCURSEL, 0, 0))));
		if (index == win32.LB_ERR) return;
		const len: isize = @bitCast(win32.SendMessageW(self.properties_list, win32.LB_GETTEXTLEN, @intCast(index), 0));
		if (len == win32.LB_ERR) return;
		const buffer = std.heap.page_allocator.alloc(u16, @as(usize, @intCast(len)) + 1) catch return;
		defer std.heap.page_allocator.free(buffer);
		_ = win32.SendMessageW(self.properties_list, win32.LB_GETTEXT, @intCast(index), ptrToLparam(buffer.ptr));
		if (win32.OpenClipboard(self.hwnd) == 0) return;
		defer _ = win32.CloseClipboard();
		_ = win32.EmptyClipboard();
		const byte_count = (@as(usize, @intCast(len)) + 1) * @sizeOf(u16);
		const mem = win32.GlobalAlloc(win32.GMEM_MOVEABLE, byte_count);
		if (mem == null) return;
		const dest = win32.GlobalLock(mem);
		if (dest == null) {
			_ = win32.GlobalFree(mem);
			return;
		}
		const dest_slice: [*]u16 = @ptrCast(@alignCast(dest));
		@memcpy(dest_slice[0 .. @as(usize, @intCast(len)) + 1], buffer);
		_ = win32.GlobalUnlock(mem);
		if (win32.SetClipboardData(win32.CF_UNICODETEXT, mem) == null) _ = win32.GlobalFree(mem);
	}
};
