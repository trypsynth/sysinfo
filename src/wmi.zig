// Port of src/wmi/{wmi_connection,wmi_row,wmi_date_time}.cpp, hand rolled COM bindings, no zigwin32.
const std = @import("std");

pub const HRESULT = i32;
pub const ULONG = u32;
pub const LONG = i32;
pub const BSTR = ?[*:0]u16;
pub const LPCWSTR = [*:0]const u16;
const S_OK: HRESULT = 0;

pub const GUID = extern struct {
	data1: u32,
	data2: u16,
	data3: u16,
	data4: [8]u8,
};

const IID_IWbemLocator = GUID{ .data1 = 0xdc12a687, .data2 = 0x737f, .data3 = 0x11cf, .data4 = .{ 0x88, 0x4d, 0x00, 0xaa, 0x00, 0x4b, 0x2e, 0x24 } };
const CLSID_WbemLocator = GUID{ .data1 = 0x4590f811, .data2 = 0x1d3a, .data3 = 0x11d0, .data4 = .{ 0x89, 0x1f, 0x00, 0xaa, 0x00, 0x4b, 0x2e, 0x24 } };

extern "ole32" fn CoInitializeEx(reserved: ?*anyopaque, dwCoInit: u32) callconv(.c) HRESULT;
extern "ole32" fn CoUninitialize() callconv(.c) void;
extern "ole32" fn CoInitializeSecurity(pSecDesc: ?*anyopaque, cAuthSvc: LONG, asAuthSvc: ?*anyopaque, pReserved1: ?*anyopaque, dwAuthnLevel: u32, dwImpLevel: u32, pAuthList: ?*anyopaque, dwCapabilities: u32, pReserved3: ?*anyopaque) callconv(.c) HRESULT;
extern "ole32" fn CoCreateInstance(rclsid: *const GUID, pUnkOuter: ?*anyopaque, dwClsContext: u32, riid: *const GUID, ppv: *?*anyopaque) callconv(.c) HRESULT;
extern "ole32" fn CoSetProxyBlanket(pProxy: *anyopaque, dwAuthnSvc: u32, dwAuthzSvc: u32, pServerPrincName: ?*anyopaque, dwAuthnLevel: u32, dwImpLevel: u32, pAuthInfo: ?*anyopaque, dwCapabilities: u32) callconv(.c) HRESULT;

extern "oleaut32" fn SysAllocString(psz: LPCWSTR) callconv(.c) BSTR;
extern "oleaut32" fn SysFreeString(bstr: BSTR) callconv(.c) void;
extern "oleaut32" fn VariantClear(pvarg: *VARIANT) callconv(.c) HRESULT;
extern "oleaut32" fn VariantInit(pvarg: *VARIANT) callconv(.c) void;
extern "oleaut32" fn VariantChangeType(dest: *VARIANT, src: *VARIANT, wFlags: u16, vt: u16) callconv(.c) HRESULT;
extern "oleaut32" fn SafeArrayGetLBound(psa: *anyopaque, nDim: u32, plLbound: *LONG) callconv(.c) HRESULT;
extern "oleaut32" fn SafeArrayGetUBound(psa: *anyopaque, nDim: u32, plUbound: *LONG) callconv(.c) HRESULT;
extern "oleaut32" fn SafeArrayGetElement(psa: *anyopaque, rgIndices: *LONG, pv: *anyopaque) callconv(.c) HRESULT;

pub const VARIANT = extern struct {
	vt: u16,
	reserved1: u16 = 0,
	reserved2: u16 = 0,
	reserved3: u16 = 0,
	payload: [8]u8 = undefined,

	fn payloadAs(self: *const VARIANT, comptime T: type) T {
		return @as(*align(1) const T, @ptrCast(&self.payload)).*;
	}
	pub fn bstrVal(self: *const VARIANT) BSTR {
		return self.payloadAs(BSTR);
	}
	pub fn boolVal(self: *const VARIANT) i16 {
		return self.payloadAs(i16);
	}
	pub fn parray(self: *const VARIANT) ?*anyopaque {
		return self.payloadAs(?*anyopaque);
	}
};

const VT_EMPTY: u16 = 0;
const VT_NULL: u16 = 1;
const VT_I4: u16 = 3;
const VT_BOOL: u16 = 11;
const VT_UI1: u16 = 17;
const VT_BSTR: u16 = 8;
const VT_ARRAY: u16 = 0x2000;
const VT_TYPEMASK: u16 = 0xfff;

const IUnknownVtbl = extern struct {
	QueryInterface: *const fn (self: *anyopaque, riid: *const GUID, out: *?*anyopaque) callconv(.c) HRESULT,
	AddRef: *const fn (self: *anyopaque) callconv(.c) ULONG,
	Release: *const fn (self: *anyopaque) callconv(.c) ULONG,
};

const IWbemLocatorVtbl = extern struct {
	unknown: IUnknownVtbl,
	ConnectServer: *const fn (self: *IWbemLocator, strNetworkResource: BSTR, strUser: BSTR, strPassword: BSTR, strLocale: BSTR, lSecurityFlags: LONG, strAuthority: BSTR, pCtx: ?*anyopaque, ppNamespace: *?*IWbemServices) callconv(.c) HRESULT,
};
const IWbemLocator = extern struct { vtbl: *const IWbemLocatorVtbl };

const IWbemServicesVtbl = extern struct {
	unknown: IUnknownVtbl,
	OpenNamespace: *const anyopaque,
	CancelAsyncCall: *const anyopaque,
	QueryObjectSink: *const anyopaque,
	GetObject: *const anyopaque,
	GetObjectAsync: *const anyopaque,
	PutClass: *const anyopaque,
	PutClassAsync: *const anyopaque,
	DeleteClass: *const anyopaque,
	DeleteClassAsync: *const anyopaque,
	CreateClassEnum: *const anyopaque,
	CreateClassEnumAsync: *const anyopaque,
	PutInstance: *const anyopaque,
	PutInstanceAsync: *const anyopaque,
	DeleteInstance: *const anyopaque,
	DeleteInstanceAsync: *const anyopaque,
	CreateInstanceEnum: *const anyopaque,
	CreateInstanceEnumAsync: *const anyopaque,
	ExecQuery: *const fn (self: *IWbemServices, strQueryLanguage: BSTR, strQuery: BSTR, lFlags: LONG, pCtx: ?*anyopaque, ppEnum: *?*IEnumWbemClassObject) callconv(.c) HRESULT,
};
pub const IWbemServices = extern struct { vtbl: *const IWbemServicesVtbl };

const IEnumWbemClassObjectVtbl = extern struct {
	unknown: IUnknownVtbl,
	Reset: *const anyopaque,
	Next: *const fn (self: *IEnumWbemClassObject, lTimeout: LONG, uCount: ULONG, apObjects: [*]?*IWbemClassObject, puReturned: *ULONG) callconv(.c) HRESULT,
};
const IEnumWbemClassObject = extern struct { vtbl: *const IEnumWbemClassObjectVtbl };

const IWbemClassObjectVtbl = extern struct {
	unknown: IUnknownVtbl,
	GetQualifierSet: *const anyopaque,
	Get: *const fn (self: *IWbemClassObject, wszName: LPCWSTR, lFlags: LONG, pVal: ?*VARIANT, pType: ?*i32, plFlavor: ?*LONG) callconv(.c) HRESULT,
};
pub const IWbemClassObject = extern struct { vtbl: *const IWbemClassObjectVtbl };

fn release(unk: anytype) void {
	_ = unk.vtbl.unknown.Release(unk);
}

/// Converts a raw CIM_DATETIME string (e.g. "20250110083000.000000-480") into "YYYY-MM-DD HH:MM:SS". Returns the input unchanged if it doesn't look like a CIM datetime.
pub fn formatWmiDateTime(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
	if (raw.len < 14) return allocator.dupe(u8, raw);
	return std.fmt.allocPrint(allocator, "{s}-{s}-{s} {s}:{s}:{s}", .{ raw[0..4], raw[4..6], raw[6..8], raw[8..10], raw[10..12], raw[12..14] });
}

/// Move only wrapper around a single WMI result object.
pub const WmiRow = struct {
	obj: *IWbemClassObject,

	pub fn deinit(self: *const WmiRow) void {
		release(self.obj);
	}

	fn rawGet(self: *const WmiRow, allocator: std.mem.Allocator, property: []const u8) !VARIANT {
		const wide_prop = try std.unicode.utf8ToUtf16LeAllocZ(allocator, property);
		defer allocator.free(wide_prop);
		var v: VARIANT = undefined;
		VariantInit(&v);
		const hr = self.obj.vtbl.Get(self.obj, wide_prop.ptr, 0, &v, null, null);
		if (hr < 0) return error.WmiGetFailed;
		return v;
	}

	fn bstrToUtf8(allocator: std.mem.Allocator, b: BSTR) ![]u8 {
		const ptr = b orelse return allocator.dupe(u8, "");
		var len: usize = 0;
		while (ptr[len] != 0) : (len += 1) {}
		return std.unicode.utf16LeToUtf8Alloc(allocator, ptr[0..len]);
	}

	fn arrayToList(allocator: std.mem.Allocator, v: *const VARIANT) ![][]u8 {
		var result = std.ArrayList([]u8).empty;
		errdefer {
			for (result.items) |s| allocator.free(s);
			result.deinit(allocator);
		}
		const arr = v.parray() orelse return result.toOwnedSlice(allocator);
		const elem_type = v.vt & VT_TYPEMASK;
		var lower: LONG = 0;
		var upper: LONG = -1;
		_ = SafeArrayGetLBound(arr, 1, &lower);
		_ = SafeArrayGetUBound(arr, 1, &upper);
		var i = lower;
		while (i <= upper) : (i += 1) {
			var index = i;
			switch (elem_type) {
				VT_BSTR => {
					var s: BSTR = null;
					if (SafeArrayGetElement(arr, &index, @ptrCast(&s)) == S_OK and s != null) {
						defer SysFreeString(s);
						const utf8 = try bstrToUtf8(allocator, s);
						if (utf8.len > 0) try result.append(allocator, utf8) else allocator.free(utf8);
					}
				},
				VT_I4 => {
					var val: i32 = 0;
					if (SafeArrayGetElement(arr, &index, @ptrCast(&val)) == S_OK) try result.append(allocator, try std.fmt.allocPrint(allocator, "{d}", .{val}));
				},
				VT_UI1 => {
					var val: u8 = 0;
					if (SafeArrayGetElement(arr, &index, @ptrCast(&val)) == S_OK) try result.append(allocator, try std.fmt.allocPrint(allocator, "{d}", .{val}));
				},
				else => {},
			}
		}
		return result.toOwnedSlice(allocator);
	}

	fn variantToUtf8(allocator: std.mem.Allocator, v: *VARIANT) ![]u8 {
		if (v.vt == VT_NULL or v.vt == VT_EMPTY) return allocator.dupe(u8, "");
		if (v.vt & VT_ARRAY != 0) {
			const list = try arrayToList(allocator, v);
			defer {
				for (list) |s| allocator.free(s);
				allocator.free(list);
			}
			return std.mem.join(allocator, ", ", list);
		}
		if (v.vt == VT_BSTR) return bstrToUtf8(allocator, v.bstrVal());
		// VariantChangeType renders VARIANT_BOOL as "-1"/"0", not readable text, so handle it explicitly like the C++ version does.
		if (v.vt == VT_BOOL) return allocator.dupe(u8, if (v.boolVal() != 0) "True" else "False");
		var dest: VARIANT = undefined;
		VariantInit(&dest);
		defer _ = VariantClear(&dest);
		if (VariantChangeType(&dest, v, 0, VT_BSTR) < 0 or dest.bstrVal() == null) return allocator.dupe(u8, "");
		return bstrToUtf8(allocator, dest.bstrVal());
	}

	/// Returns the property formatted as text, or "" if missing/null. Caller owns the returned slice.
	pub fn get(self: *const WmiRow, allocator: std.mem.Allocator, property: []const u8) ![]u8 {
		var v = self.rawGet(allocator, property) catch return allocator.dupe(u8, "");
		defer _ = VariantClear(&v);
		return variantToUtf8(allocator, &v);
	}

	/// Returns a multi-valued (array) property as separate elements. Caller owns the returned slice and each string in it.
	pub fn getList(self: *const WmiRow, allocator: std.mem.Allocator, property: []const u8) ![][]u8 {
		var v = self.rawGet(allocator, property) catch return &.{};
		defer _ = VariantClear(&v);
		if (v.vt & VT_ARRAY == 0) return &.{};
		return arrayToList(allocator, &v);
	}
};

/// Lazily initialized, process wide WMI connection. Callers never touch COM/WBEM directly, they call query() with a WQL string and a namespace.
pub const WmiConnection = struct {
	com_initialized: bool,
	locator: *IWbemLocator,
	services_by_namespace: std.StringHashMap(*IWbemServices),
	allocator: std.mem.Allocator,

	var instance_storage: ?WmiConnection = null;

	pub fn instance(allocator: std.mem.Allocator) !*WmiConnection {
		if (instance_storage == null) instance_storage = try WmiConnection.init(allocator);
		return &instance_storage.?;
	}

	fn init(allocator: std.mem.Allocator) !WmiConnection {
		var hr = CoInitializeEx(null, 2);
		const RPC_E_CHANGED_MODE: HRESULT = @bitCast(@as(u32, 0x80010106));
		if (hr < 0 and hr != RPC_E_CHANGED_MODE) return error.ComInitFailed;
		const com_initialized = hr != RPC_E_CHANGED_MODE;
		hr = CoInitializeSecurity(null, -1, null, null, 1, 3, null, 0, null);
		const RPC_E_TOO_LATE: HRESULT = @bitCast(@as(u32, 0x80010119));
		if (hr < 0 and hr != RPC_E_TOO_LATE) return error.SecurityInitFailed;
		var locator_opt: ?*anyopaque = null;
		hr = CoCreateInstance(&CLSID_WbemLocator, null, 1, &IID_IWbemLocator, &locator_opt);
		if (hr < 0 or locator_opt == null) return error.CreateLocatorFailed;
		return .{ .com_initialized = com_initialized, .locator = @ptrCast(@alignCast(locator_opt.?)), .services_by_namespace = std.StringHashMap(*IWbemServices).init(allocator), .allocator = allocator };
	}

	fn connect(self: *WmiConnection, wmi_namespace: []const u8) !*IWbemServices {
		if (self.services_by_namespace.get(wmi_namespace)) |svc| return svc;
		const wide_ns = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, wmi_namespace);
		defer self.allocator.free(wide_ns);
		const ns_bstr = SysAllocString(wide_ns.ptr);
		defer SysFreeString(ns_bstr);
		var services_opt: ?*IWbemServices = null;
		var hr = self.locator.vtbl.ConnectServer(self.locator, ns_bstr, null, null, null, 0, null, null, &services_opt);
		if (hr < 0 or services_opt == null) return error.ConnectServerFailed;
		const services = services_opt.?;
		hr = CoSetProxyBlanket(services, 10, 0, null, 3, 3, null, 0);
		if (hr < 0) {
			release(services);
			return error.ProxyBlanketFailed;
		}
		const key = try self.allocator.dupe(u8, wmi_namespace);
		try self.services_by_namespace.put(key, services);
		return services;
	}

	/// Throws on failure. Caller owns the returned slice and must deinit() each row.
	pub fn query(self: *WmiConnection, allocator: std.mem.Allocator, wql: []const u8, wmi_namespace: []const u8) ![]WmiRow {
		const services = try self.connect(wmi_namespace);
		const wide_wql = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, wql);
		defer self.allocator.free(wide_wql);
		const lang = SysAllocString(std.unicode.utf8ToUtf16LeStringLiteral("WQL"));
		defer SysFreeString(lang);
		const query_bstr = SysAllocString(wide_wql.ptr);
		defer SysFreeString(query_bstr);
		var enumerator_opt: ?*IEnumWbemClassObject = null;
		const hr = services.vtbl.ExecQuery(services, lang, query_bstr, 0x10 | 0x20, null, &enumerator_opt);
		if (hr < 0 or enumerator_opt == null) return error.ExecQueryFailed;
		const enumerator = enumerator_opt.?;
		defer release(enumerator);
		var rows = std.ArrayList(WmiRow).empty;
		errdefer {
			for (rows.items) |*r| r.deinit();
			rows.deinit(allocator);
		}
		while (true) {
			var obj_opt: ?*IWbemClassObject = null;
			var returned: ULONG = 0;
			const next_hr = enumerator.vtbl.Next(enumerator, -1, 1, @ptrCast(&obj_opt), &returned);
			if (next_hr != S_OK or obj_opt == null) break;
			try rows.append(allocator, .{ .obj = obj_opt.? });
		}
		return rows.toOwnedSlice(allocator);
	}
};
