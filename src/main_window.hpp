#pragma once
#include <vector>
#include <windows.h>
#include "core/category_item.hpp"

// The main window is a modeless dialog rather than a plain CreateWindowEx window. That's what makes Windows automatically derive each listbox's accessible Name from its preceding STATIC label, and what makes Tab move focus between controls (both are dialog-manager behaviors, not things a plain top-level window gets for free) - see main.cpp's use of IsDialogMessage.
class main_window {
public:
	explicit main_window(HINSTANCE instance);
	HWND create();
	HACCEL accelerator_table() const { return accelerators_; }
private:
	static INT_PTR CALLBACK dialog_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam);
	INT_PTR handle_message(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam);
	void on_init_dialog(HWND hwnd);
	void on_size(int width, int height);
	void on_command(WPARAM wparam, LPARAM lparam);
	void refresh_categories();
	void populate_properties(int category_index);
	void copy_selected_property();
	HINSTANCE instance_;
	HWND hwnd_ = nullptr;
	HWND categories_label_ = nullptr;
	HWND categories_list_ = nullptr;
	HWND properties_label_ = nullptr;
	HWND properties_list_ = nullptr;
	HACCEL accelerators_ = nullptr;
	std::vector<category_item> items_;
};
