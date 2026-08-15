// Hand rolled, non COM Win32 bindings used by main_window.zig and a few providers.
const std = @import("std");

pub const HWND = ?*anyopaque;
pub const HINSTANCE = ?*anyopaque;
pub const HMENU = ?*anyopaque;
pub const HACCEL = ?*anyopaque;
pub const HFONT = ?*anyopaque;
pub const HGDIOBJ = ?*anyopaque;
pub const HGLOBAL = ?*anyopaque;
pub const HKEY = ?*anyopaque;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;
pub const INT_PTR = isize;
pub const UINT = u32;
pub const DWORD = u32;
pub const WORD = u16;
pub const BYTE = u8;
pub const BOOL = i32;
pub const LONG = i32;
pub const LSTATUS = i32;
pub const LPCWSTR = [*:0]const u16;

pub const POINT = extern struct {
	x: i32,
	y: i32,
};

pub const MSG = extern struct {
	hwnd: HWND,
	message: UINT,
	wParam: WPARAM,
	lParam: LPARAM,
	time: DWORD,
	pt: POINT,
};

pub const ACCEL = extern struct {
	fVirt: BYTE,
	key: WORD,
	cmd: WORD,
};

pub const DISPLAY_DEVICEW = extern struct {
	cb: DWORD,
	DeviceName: [32]u16,
	DeviceString: [128]u16,
	StateFlags: DWORD,
	DeviceID: [128]u16,
	DeviceKey: [128]u16,
};

pub const DEVMODEW = extern struct {
	dmDeviceName: [32]u16,
	dmSpecVersion: WORD,
	dmDriverVersion: WORD,
	dmSize: WORD,
	dmDriverExtra: WORD,
	dmFields: DWORD,
	dmUnion1: [4]u32,
	dmColor: i16,
	dmDuplex: i16,
	dmYResolution: i16,
	dmTTOption: i16,
	dmCollate: i16,
	dmFormName: [32]u16,
	dmLogPixels: WORD,
	dmBitsPerPel: DWORD,
	dmPelsWidth: DWORD,
	dmPelsHeight: DWORD,
	dmUnion2: u32,
	dmDisplayFrequency: DWORD,
	dmICMMethod: DWORD,
	dmICMIntent: DWORD,
	dmMediaType: DWORD,
	dmDitherType: DWORD,
	dmReserved1: DWORD,
	dmReserved2: DWORD,
	dmPanningWidth: DWORD,
	dmPanningHeight: DWORD,
};

pub const DlgProc = *const fn (hwnd: HWND, msg: UINT, wparam: WPARAM, lparam: LPARAM) callconv(.c) INT_PTR;

pub const FIRMWARE_TYPE_UNKNOWN: u32 = 0;
pub const FIRMWARE_TYPE_BIOS: u32 = 1;
pub const FIRMWARE_TYPE_UEFI: u32 = 2;
pub const HKEY_LOCAL_MACHINE: HKEY = @ptrFromInt(0x80000002);
pub const RRF_RT_REG_DWORD: DWORD = 0x00000010;
pub const ERROR_SUCCESS: LSTATUS = 0;
pub const DISPLAY_DEVICE_ATTACHED_TO_DESKTOP: DWORD = 0x00000001;
pub const DISPLAY_DEVICE_PRIMARY_DEVICE: DWORD = 0x00000004;
pub const ENUM_CURRENT_SETTINGS: DWORD = 0xFFFFFFFE;
pub const SM_CXSCREEN: i32 = 0;
pub const SM_CYSCREEN: i32 = 1;
pub const SWP_NOZORDER: UINT = 0x0004;
pub const WS_CHILD: DWORD = 0x40000000;
pub const WS_VISIBLE: DWORD = 0x10000000;
pub const WS_VSCROLL: DWORD = 0x00200000;
pub const WS_TABSTOP: DWORD = 0x00010000;
pub const WS_GROUP: DWORD = 0x00020000;
pub const WS_POPUP: DWORD = 0x80000000;
pub const WS_CAPTION: DWORD = 0x00C00000;
pub const WS_SYSMENU: DWORD = 0x00080000;
pub const WS_THICKFRAME: DWORD = 0x00040000;
pub const WS_MINIMIZEBOX: DWORD = 0x00020000;
pub const WS_MAXIMIZEBOX: DWORD = 0x00010000;
pub const WS_CLIPCHILDREN: DWORD = 0x02000000;
pub const WS_EX_CLIENTEDGE: DWORD = 0x00000200;
pub const LBS_NOTIFY: DWORD = 0x0001;
pub const LBS_HASSTRINGS: DWORD = 0x0040;
pub const DS_SETFONT: DWORD = 0x40;
pub const MF_STRING: UINT = 0x00000000;
pub const MF_SEPARATOR: UINT = 0x00000800;
pub const MF_POPUP: UINT = 0x00000010;
pub const LBN_SELCHANGE: WORD = 1;
pub const DEFAULT_GUI_FONT: i32 = 17;
pub const FVIRTKEY: BYTE = 0x01;
pub const FCONTROL: BYTE = 0x08;
pub const VK_F5: WORD = 0x74;
pub const GWLP_USERDATA: i32 = -21;
pub const GMEM_MOVEABLE: UINT = 0x0002;
pub const CF_UNICODETEXT: UINT = 13;
pub const WM_INITDIALOG: UINT = 0x0110;
pub const WM_SIZE: UINT = 0x0005;
pub const WM_COMMAND: UINT = 0x0111;
pub const WM_CLOSE: UINT = 0x0010;
pub const WM_DESTROY: UINT = 0x0002;
pub const WM_SETFONT: UINT = 0x0030;
pub const LB_RESETCONTENT: UINT = 0x0184;
pub const LB_ADDSTRING: UINT = 0x0180;
pub const LB_SETCURSEL: UINT = 0x0186;
pub const LB_GETCURSEL: UINT = 0x0188;
pub const LB_GETTEXT: UINT = 0x0189;
pub const LB_GETTEXTLEN: UINT = 0x018A;
pub const LB_GETCOUNT: UINT = 0x018B;
pub const LB_ERR: LRESULT = -1;
pub const IDCANCEL: i32 = 2;
pub const SW_SHOWDEFAULT: i32 = 10;

pub extern "kernel32" fn GetModuleHandleW(lpModuleName: ?LPCWSTR) callconv(.c) HINSTANCE;

pub extern "kernel32" fn GetFirmwareType(FirmwareType: *u32) callconv(.c) BOOL;
pub extern "kernel32" fn GetPhysicallyInstalledSystemMemory(TotalMemoryInKilobytes: *u64) callconv(.c) BOOL;
pub extern "kernel32" fn GetTickCount64() callconv(.c) u64;
pub extern "advapi32" fn RegGetValueW(hkey: HKEY, lpSubKey: LPCWSTR, lpValue: LPCWSTR, dwFlags: DWORD, pdwType: ?*DWORD, pvData: ?*anyopaque, pcbData: ?*DWORD) callconv(.c) LSTATUS;
pub extern "user32" fn EnumDisplayDevicesW(lpDevice: ?LPCWSTR, iDevNum: DWORD, lpDisplayDevice: *DISPLAY_DEVICEW, dwFlags: DWORD) callconv(.c) BOOL;
pub extern "user32" fn EnumDisplaySettingsW(lpszDeviceName: ?LPCWSTR, iModeNum: DWORD, lpDevMode: *DEVMODEW) callconv(.c) BOOL;
pub extern "user32" fn CreateDialogIndirectParamW(hInstance: HINSTANCE, lpTemplate: *const anyopaque, hWndParent: HWND, lpDialogFunc: DlgProc, dwInitParam: LPARAM) callconv(.c) HWND;
pub extern "user32" fn GetSystemMetrics(nIndex: i32) callconv(.c) i32;
pub extern "user32" fn SetWindowPos(hWnd: HWND, hWndInsertAfter: HWND, X: i32, Y: i32, cx: i32, cy: i32, uFlags: UINT) callconv(.c) BOOL;
pub extern "user32" fn CreateWindowExW(dwExStyle: DWORD, lpClassName: LPCWSTR, lpWindowName: ?LPCWSTR, dwStyle: DWORD, X: i32, Y: i32, nWidth: i32, nHeight: i32, hWndParent: HWND, hMenu: HMENU, hInstance: HINSTANCE, lpParam: ?*anyopaque) callconv(.c) HWND;
pub extern "user32" fn SendMessageW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.c) LRESULT;
pub extern "gdi32" fn GetStockObject(i: i32) callconv(.c) HGDIOBJ;
pub extern "user32" fn CreatePopupMenu() callconv(.c) HMENU;
pub extern "user32" fn AppendMenuW(hMenu: HMENU, uFlags: UINT, uIDNewItem: usize, lpNewItem: ?LPCWSTR) callconv(.c) BOOL;
pub extern "user32" fn CreateMenu() callconv(.c) HMENU;
pub extern "user32" fn SetMenu(hWnd: HWND, hMenu: HMENU) callconv(.c) BOOL;
pub extern "user32" fn CreateAcceleratorTableW(paccel: [*]const ACCEL, cAccel: i32) callconv(.c) HACCEL;
pub extern "user32" fn MoveWindow(hWnd: HWND, X: i32, Y: i32, nWidth: i32, nHeight: i32, bRepaint: BOOL) callconv(.c) BOOL;
pub extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.c) BOOL;
pub extern "user32" fn PostQuitMessage(nExitCode: i32) callconv(.c) void;
pub extern "user32" fn SetWindowLongPtrW(hWnd: HWND, nIndex: i32, dwNewLong: isize) callconv(.c) isize;
pub extern "user32" fn GetWindowLongPtrW(hWnd: HWND, nIndex: i32) callconv(.c) isize;
pub extern "user32" fn GetFocus() callconv(.c) HWND;
pub extern "user32" fn SetFocus(hWnd: HWND) callconv(.c) HWND;
pub extern "user32" fn OpenClipboard(hWndNewOwner: HWND) callconv(.c) BOOL;
pub extern "user32" fn EmptyClipboard() callconv(.c) BOOL;
pub extern "kernel32" fn GlobalAlloc(uFlags: UINT, dwBytes: usize) callconv(.c) HGLOBAL;
pub extern "kernel32" fn GlobalLock(hMem: HGLOBAL) callconv(.c) ?*anyopaque;
pub extern "kernel32" fn GlobalUnlock(hMem: HGLOBAL) callconv(.c) BOOL;
pub extern "kernel32" fn GlobalFree(hMem: HGLOBAL) callconv(.c) HGLOBAL;
pub extern "user32" fn SetClipboardData(uFormat: UINT, hMem: HGLOBAL) callconv(.c) HGLOBAL;
pub extern "user32" fn CloseClipboard() callconv(.c) BOOL;
pub extern "user32" fn TranslateAcceleratorW(hWnd: HWND, hAccTable: HACCEL, lpMsg: *MSG) callconv(.c) i32;
pub extern "user32" fn IsDialogMessageW(hDlg: HWND, lpMsg: *MSG) callconv(.c) BOOL;
pub extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.c) BOOL;
pub extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.c) isize;
pub extern "user32" fn GetMessageW(lpMsg: *MSG, hWnd: HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT) callconv(.c) BOOL;
pub extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(.c) BOOL;
pub extern "user32" fn UpdateWindow(hWnd: HWND) callconv(.c) BOOL;

pub fn loword(l: LPARAM) u16 {
	return @truncate(@as(usize, @bitCast(l)) & 0xffff);
}

pub fn hiword(l: LPARAM) u16 {
	return @truncate((@as(usize, @bitCast(l)) >> 16) & 0xffff);
}
