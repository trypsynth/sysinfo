#include <windows.h>
#include "main_window.hpp"

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, LPWSTR, int show_cmd) {
	main_window window(instance);
	HWND hwnd = window.create();
	if (!hwnd) return 0;
	ShowWindow(hwnd, show_cmd);
	UpdateWindow(hwnd);
	MSG msg;
	while (GetMessageW(&msg, nullptr, 0, 0)) {
		if (TranslateAcceleratorW(hwnd, window.accelerator_table(), &msg)) continue;
		if (IsDialogMessageW(hwnd, &msg)) continue;
		TranslateMessage(&msg);
		DispatchMessageW(&msg);
	}
	return static_cast<int>(msg.wParam);
}
