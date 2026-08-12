#include "wmi_row.hpp"
#include <oleauto.h>

namespace {
std::vector<std::wstring> variant_array_to_list(const VARIANT& var) {
	std::vector<std::wstring> result;
	SAFEARRAY* arr = var.parray;
	if (!arr) return result;
	VARTYPE elem_type = var.vt & VT_TYPEMASK;
	long lower_bound = 0, upper_bound = -1;
	SafeArrayGetLBound(arr, 1, &lower_bound);
	SafeArrayGetUBound(arr, 1, &upper_bound);
	for (long i = lower_bound; i <= upper_bound; ++i) {
		std::wstring part;
		switch (elem_type) {
			case VT_BSTR: {
				BSTR s = nullptr;
				if (SUCCEEDED(SafeArrayGetElement(arr, &i, &s)) && s) { part = s; SysFreeString(s); }
				break;
			}
			case VT_I4: {
				long v = 0;
				if (SUCCEEDED(SafeArrayGetElement(arr, &i, &v))) part = std::to_wstring(v);
				break;
			}
			case VT_UI1: {
				BYTE v = 0;
				if (SUCCEEDED(SafeArrayGetElement(arr, &i, &v))) part = std::to_wstring(v);
				break;
			}
			default:
				break;
		}
		if (!part.empty()) result.push_back(part);
	}
	return result;
}

std::wstring variant_array_to_wstring(const VARIANT& var) {
	std::wstring joined;
	auto list = variant_array_to_list(var);
	for (size_t i = 0; i < list.size(); ++i) {
		if (i) joined += L", ";
		joined += list[i];
	}
	return joined;
}

std::wstring variant_to_wstring(const VARIANT& var) {
	if (var.vt == VT_NULL || var.vt == VT_EMPTY) return L"";
	if (var.vt & VT_ARRAY) return variant_array_to_wstring(var);
	if (var.vt == VT_BSTR) return var.bstrVal ? std::wstring(var.bstrVal) : L"";
	// VariantChangeType would convert this to "-1"/"0" (its default numeric rendering of VARIANT_BOOL), not readable text - handle it explicitly instead.
	if (var.vt == VT_BOOL) return var.boolVal ? L"True" : L"False";
	VARIANT src = var;  // shallow copy: VariantChangeType only writes to dest.
	VARIANT dest;
	VariantInit(&dest);
	std::wstring result;
	if (SUCCEEDED(VariantChangeType(&dest, &src, 0, VT_BSTR)) && dest.bstrVal) result = dest.bstrVal;
	VariantClear(&dest);
	return result;
}
}  // namespace

wmi_row::wmi_row(IWbemClassObject* obj) : obj_(obj) {}

wmi_row::~wmi_row() {
	if (obj_) obj_->Release();
}

wmi_row::wmi_row(wmi_row&& other) noexcept : obj_(other.obj_) { other.obj_ = nullptr; }

wmi_row& wmi_row::operator=(wmi_row&& other) noexcept {
	if (this != &other) {
		if (obj_) obj_->Release();
		obj_ = other.obj_;
		other.obj_ = nullptr;
	}
	return *this;
}

std::wstring wmi_row::get(const wchar_t* property) const {
	if (!obj_) return L"";
	VARIANT var;
	VariantInit(&var);
	std::wstring result;
	if (SUCCEEDED(obj_->Get(property, 0, &var, nullptr, nullptr))) result = variant_to_wstring(var);
	VariantClear(&var);
	return result;
}

std::vector<std::wstring> wmi_row::get_list(const wchar_t* property) const {
	std::vector<std::wstring> result;
	if (!obj_) return result;
	VARIANT var;
	VariantInit(&var);
	if (SUCCEEDED(obj_->Get(property, 0, &var, nullptr, nullptr)) && (var.vt & VT_ARRAY)) result = variant_array_to_list(var);
	VariantClear(&var);
	return result;
}
