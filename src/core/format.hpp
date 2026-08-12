#pragma once
#include <string>

// Parses a decimal byte-count string and renders it as e.g. "11.5 GB".
// Returns the input unchanged if it isn't a parseable number.
std::wstring format_bytes_as_gb(const std::wstring& bytes_str);

// Appends suffix to value, e.g. with_unit(L"4800", L" MHz") -> L"4800 MHz". Returns "" unchanged if value is empty, so a missing property still gets filtered out instead of showing a bare unit.
std::wstring with_unit(const std::wstring& value, const std::wstring& suffix);
