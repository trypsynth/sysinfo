#include "main_window.hpp"
#include <algorithm>
#include <exception>
#include <iterator>
#include "core/provider_registry.hpp"

namespace {
constexpr int categories_label_id = 101;
constexpr int categories_list_id = 102;
constexpr int properties_label_id = 103;
constexpr int properties_list_id = 104;
constexpr int menu_refresh_id = 201;
constexpr int menu_exit_id = 202;
constexpr int menu_copy_id = 203;

// Builds a minimal in-memory DLGTEMPLATE with zero template-defined items; every control is created by hand in on_init_dialog. Using the predefined dialog class (windowClass = 0) is what gets us free accessible-name association between each STATIC label and the control after it, plus Tab-key navigation via IsDialogMessage - neither works for a plain CreateWindowEx window. Only the outer size is approximate here; create() overrides it in real pixels via SetWindowPos right after creation.
std::vector<BYTE> build_dialog_template(const std::wstring& title) {
	std::vector<BYTE> buffer;
	auto append_word = [&](WORD w) { auto* p = reinterpret_cast<BYTE*>(&w); buffer.insert(buffer.end(), p, p + sizeof(WORD)); };
	auto append_dword = [&](DWORD d) { auto* p = reinterpret_cast<BYTE*>(&d); buffer.insert(buffer.end(), p, p + sizeof(DWORD)); };
	auto append_wstring = [&](const std::wstring& s) { auto* p = reinterpret_cast<const BYTE*>(s.c_str()); buffer.insert(buffer.end(), p, p + (s.size() + 1) * sizeof(wchar_t)); };
	const DWORD style = DS_SETFONT | WS_POPUP | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_CLIPCHILDREN;
	append_dword(style);
	append_dword(0);
	append_word(0);
	append_word(0);
	append_word(0);
	append_word(300);
	append_word(200);
	append_word(0);
	append_word(0);
	append_wstring(title);
	append_word(8);
	append_wstring(L"MS Shell Dlg");
	return buffer;
}
}  // namespace

main_window::main_window(HINSTANCE instance) : instance_(instance) {}

HWND main_window::create() {
	std::vector<BYTE> tmpl = build_dialog_template(L"System Information");
	hwnd_ = CreateDialogIndirectParamW(instance_, reinterpret_cast<LPCDLGTEMPLATE>(tmpl.data()), nullptr, dialog_proc, reinterpret_cast<LPARAM>(this));
	if (hwnd_) {
		const int width = 900;
		const int height = 600;
		const int screen_width = GetSystemMetrics(SM_CXSCREEN);
		const int screen_height = GetSystemMetrics(SM_CYSCREEN);
		SetWindowPos(hwnd_, nullptr, (screen_width - width) / 2, (screen_height - height) / 2, width, height, SWP_NOZORDER);
	}
	return hwnd_;
}

INT_PTR CALLBACK main_window::dialog_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
	main_window* self;
	if (msg == WM_INITDIALOG) {
		self = reinterpret_cast<main_window*>(lparam);
		SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
		self->hwnd_ = hwnd;
	} else {
		self = reinterpret_cast<main_window*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
	}
	if (self) return self->handle_message(hwnd, msg, wparam, lparam);
	return FALSE;
}

INT_PTR main_window::handle_message(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
	switch (msg) {
		case WM_INITDIALOG: on_init_dialog(hwnd); return TRUE;
		case WM_SIZE: on_size(LOWORD(lparam), HIWORD(lparam)); return TRUE;
		case WM_COMMAND: on_command(wparam, lparam); return TRUE;
		case WM_CLOSE: DestroyWindow(hwnd); return TRUE;
		case WM_DESTROY: PostQuitMessage(0); return TRUE;
		default: return FALSE;
	}
}

void main_window::on_init_dialog(HWND hwnd) {
	HFONT font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
	categories_label_ = CreateWindowExW(0, L"STATIC", L"Categories", WS_CHILD | WS_VISIBLE | WS_GROUP, 0, 0, 0, 0, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(categories_label_id)), instance_, nullptr);
	categories_list_ = CreateWindowExW(WS_EX_CLIENTEDGE, L"LISTBOX", nullptr, WS_CHILD | WS_VISIBLE | WS_VSCROLL | WS_TABSTOP | LBS_NOTIFY | LBS_HASSTRINGS, 0, 0, 0, 0, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(categories_list_id)), instance_, nullptr);
	properties_label_ = CreateWindowExW(0, L"STATIC", L"Properties", WS_CHILD | WS_VISIBLE | WS_GROUP, 0, 0, 0, 0, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(properties_label_id)), instance_, nullptr);
	properties_list_ = CreateWindowExW(WS_EX_CLIENTEDGE, L"LISTBOX", nullptr, WS_CHILD | WS_VISIBLE | WS_VSCROLL | WS_TABSTOP | LBS_NOTIFY | LBS_HASSTRINGS, 0, 0, 0, 0, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(properties_list_id)), instance_, nullptr);
	for (HWND control : {categories_label_, categories_list_, properties_label_, properties_list_}) SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
	HMENU file_menu = CreatePopupMenu();
	AppendMenuW(file_menu, MF_STRING, menu_refresh_id, L"&Refresh\tF5");
	AppendMenuW(file_menu, MF_SEPARATOR, 0, nullptr);
	AppendMenuW(file_menu, MF_STRING, menu_exit_id, L"E&xit");
	HMENU edit_menu = CreatePopupMenu();
	AppendMenuW(edit_menu, MF_STRING, menu_copy_id, L"&Copy\tCtrl+C");
	HMENU menu_bar = CreateMenu();
	AppendMenuW(menu_bar, MF_POPUP, reinterpret_cast<UINT_PTR>(file_menu), L"&File");
	AppendMenuW(menu_bar, MF_POPUP, reinterpret_cast<UINT_PTR>(edit_menu), L"&Edit");
	SetMenu(hwnd, menu_bar);
	ACCEL accels[] = {{FVIRTKEY, VK_F5, menu_refresh_id}, {FVIRTKEY | FCONTROL, L'C', menu_copy_id}};
	accelerators_ = CreateAcceleratorTable(accels, static_cast<int>(std::size(accels)));
	refresh_categories();
	SetFocus(categories_list_);
}

void main_window::on_size(int width, int height) {
	if (!categories_list_) return;
	const int margin = 10;
	const int label_height = 18;
	const int half_width = (width - margin * 3) / 2;
	const int list_top = margin + label_height;
	const int list_height = height - list_top - margin;
	const int right_x = margin * 2 + half_width;
	MoveWindow(categories_label_, margin, margin, half_width, label_height, TRUE);
	MoveWindow(categories_list_, margin, list_top, half_width, list_height, TRUE);
	MoveWindow(properties_label_, right_x, margin, half_width, label_height, TRUE);
	MoveWindow(properties_list_, right_x, list_top, half_width, list_height, TRUE);
}

void main_window::on_command(WPARAM wparam, LPARAM lparam) {
	int id = LOWORD(wparam);
	if (lparam != 0) {
		if (id == categories_list_id && HIWORD(wparam) == LBN_SELCHANGE) {
			int index = static_cast<int>(SendMessageW(categories_list_, LB_GETCURSEL, 0, 0));
			populate_properties(index);
		}
		return;
	}
	switch (id) {
		case menu_refresh_id: refresh_categories(); break;
		case menu_exit_id: DestroyWindow(hwnd_); break;
		case menu_copy_id: copy_selected_property(); break;
		// IsDialogMessage turns an unhandled Escape keypress into WM_COMMAND(IDCANCEL); treat it as "close the window".
		case IDCANCEL: DestroyWindow(hwnd_); break;
	}
}

void main_window::refresh_categories() {
	SendMessageW(categories_list_, LB_RESETCONTENT, 0, 0);
	SendMessageW(properties_list_, LB_RESETCONTENT, 0, 0);
	std::vector<category_item> collected;
	for (auto& provider : provider_registry::instance().create_all()) {
		try {
			for (auto& item : provider->get_items()) collected.push_back(std::move(item));
		} catch (const std::exception&) {
			// One provider failing (e.g. a WMI class unavailable on this machine) must not take down the rest of the categories.
		}
	}
	std::sort(collected.begin(), collected.end(), [](const category_item& a, const category_item& b) { return a.label < b.label; });
	items_ = std::move(collected);
	for (const auto& item : items_) SendMessageW(categories_list_, LB_ADDSTRING, 0, reinterpret_cast<LPARAM>(item.label.c_str()));
	// Pre-select the first category (and its first property below) so a screen reader user tabbing in immediately hears something useful, instead of having to press Down arrow once just to get a selection.
	if (!items_.empty()) {
		SendMessageW(categories_list_, LB_SETCURSEL, 0, 0);
		populate_properties(0);
	}
}

void main_window::populate_properties(int category_index) {
	SendMessageW(properties_list_, LB_RESETCONTENT, 0, 0);
	if (category_index < 0 || static_cast<size_t>(category_index) >= items_.size()) return;
	for (const auto& prop : items_[category_index].properties) {
		if (prop.value.empty()) continue;
		std::wstring line = prop.name + L": " + prop.value;
		SendMessageW(properties_list_, LB_ADDSTRING, 0, reinterpret_cast<LPARAM>(line.c_str()));
	}
	if (SendMessageW(properties_list_, LB_GETCOUNT, 0, 0) > 0) SendMessageW(properties_list_, LB_SETCURSEL, 0, 0);
}

void main_window::copy_selected_property() {
	if (GetFocus() != properties_list_) return;
	int index = static_cast<int>(SendMessageW(properties_list_, LB_GETCURSEL, 0, 0));
	if (index == LB_ERR) return;
	int len = static_cast<int>(SendMessageW(properties_list_, LB_GETTEXTLEN, index, 0));
	if (len == LB_ERR) return;
	std::wstring text(static_cast<size_t>(len) + 1, L'\0');
	SendMessageW(properties_list_, LB_GETTEXT, index, reinterpret_cast<LPARAM>(text.data()));
	text.resize(static_cast<size_t>(len));
	if (!OpenClipboard(hwnd_)) return;
	EmptyClipboard();
	HGLOBAL mem = GlobalAlloc(GMEM_MOVEABLE, (text.size() + 1) * sizeof(wchar_t));
	if (mem) {
		wchar_t* dest = static_cast<wchar_t*>(GlobalLock(mem));
		if (dest) {
			wcscpy_s(dest, text.size() + 1, text.c_str());
			GlobalUnlock(mem);
			if (!SetClipboardData(CF_UNICODETEXT, mem)) GlobalFree(mem);
		} else {
			GlobalFree(mem);
		}
	}
	CloseClipboard();
}
