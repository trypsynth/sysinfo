#pragma once
#include <string>

// Formats a duration for reading aloud, e.g. "1 hour and 2 minutes" or "1 hour, 2 minutes, and 3 seconds". Zero-value leading units are omitted (no "0 days"); always produces at least one component.
std::wstring format_duration(unsigned long long total_seconds);
