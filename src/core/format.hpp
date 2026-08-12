#pragma once
#include <string>

// Parses a decimal byte count string and renders it with the best fitting unit, e.g. "11.5 GB" or "2.3 TB". Returns the input unchanged if it isn't a parseable number.
std::wstring format_bytes(const std::wstring& bytes_str);

// Appends suffix to value, e.g. with_unit(L"4800", L" MHz") -> L"4800 MHz". Returns "" unchanged if value is empty, so a missing property still gets filtered out instead of showing a bare unit.
std::wstring with_unit(const std::wstring& value, const std::wstring& suffix);

// Formats part as a percentage of whole with two decimal places, e.g. format_percent(561, 930) -> L"60.32%". Returns "" if whole is zero or negative.
std::wstring format_percent(double part, double whole);

// Formats a duration for reading aloud, e.g. "1 hour and 2 minutes" or "1 hour, 2 minutes, and 3 seconds". Zero value leading units are omitted (no "0 days"); always produces at least one component.
std::wstring format_duration(unsigned long long total_seconds);
