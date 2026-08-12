#include "wmi_connection.hpp"
#include <comdef.h>
#include <stdexcept>

#pragma comment(lib, "wbemuuid.lib")

wmi_connection& wmi_connection::instance() {
	static wmi_connection inst;
	return inst;
}

wmi_connection::wmi_connection() {
	HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
	if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) throw std::runtime_error("Failed to initialize COM");
	com_initialized_ = (hr != RPC_E_CHANGED_MODE);
	hr = CoInitializeSecurity(nullptr, -1, nullptr, nullptr, RPC_C_AUTHN_LEVEL_DEFAULT, RPC_C_IMP_LEVEL_IMPERSONATE, nullptr, EOAC_NONE, nullptr);
	if (FAILED(hr) && hr != RPC_E_TOO_LATE) throw std::runtime_error("CoInitializeSecurity failed");
	hr = CoCreateInstance(CLSID_WbemLocator, nullptr, CLSCTX_INPROC_SERVER, IID_IWbemLocator, reinterpret_cast<LPVOID*>(&locator_));
	if (FAILED(hr)) throw std::runtime_error("Failed to create WbemLocator");
}

wmi_connection::~wmi_connection() {
	for (auto& entry : services_by_namespace_) entry.second->Release();
	if (locator_) locator_->Release();
	if (com_initialized_) CoUninitialize();
}

IWbemServices* wmi_connection::connect(const std::wstring& wmi_namespace) {
	auto found = services_by_namespace_.find(wmi_namespace);
	if (found != services_by_namespace_.end()) return found->second;
	IWbemServices* services = nullptr;
	HRESULT hr = locator_->ConnectServer(_bstr_t(wmi_namespace.c_str()), nullptr, nullptr, nullptr, 0, nullptr, nullptr, &services);
	if (FAILED(hr)) throw std::runtime_error("Failed to connect to WMI namespace");
	hr = CoSetProxyBlanket(services, RPC_C_AUTHN_WINNT, RPC_C_AUTHZ_NONE, nullptr, RPC_C_AUTHN_LEVEL_CALL, RPC_C_IMP_LEVEL_IMPERSONATE, nullptr, EOAC_NONE);
	if (FAILED(hr)) {
		services->Release();
		throw std::runtime_error("Failed to set WMI proxy blanket");
	}
	services_by_namespace_[wmi_namespace] = services;
	return services;
}

std::vector<wmi_row> wmi_connection::query(const std::wstring& wql, const std::wstring& wmi_namespace) {
	IWbemServices* services = connect(wmi_namespace);
	IEnumWbemClassObject* enumerator = nullptr;
	HRESULT hr = services->ExecQuery(_bstr_t(L"WQL"), _bstr_t(wql.c_str()), WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY, nullptr, &enumerator);
	if (FAILED(hr)) throw std::runtime_error("WMI query failed");
	std::vector<wmi_row> rows;
	ULONG returned = 0;
	IWbemClassObject* obj = nullptr;
	while (enumerator->Next(WBEM_INFINITE, 1, &obj, &returned) == S_OK) {
		rows.emplace_back(obj);
		obj = nullptr;
	}
	enumerator->Release();
	return rows;
}
