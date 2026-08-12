cmake_minimum_required(VERSION 3.20)
project(sysinfo LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT WIN32)
	message(FATAL_ERROR "sysinfo is a Win32-only project")
endif()

if(NOT MSVC)
	message(FATAL_ERROR "sysinfo only targets MSVC")
endif()

# CMake's MSVC Release default is /O2 (speed); swap it for /O1 (size) since we want the smallest Release binary.
string(REPLACE "/O2" "/O1" CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE}")

file(GLOB_RECURSE PROVIDER_SOURCES CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/src/providers/*.cpp")

add_executable(sysinfo WIN32
	src/main.cpp
	src/main_window.cpp
	src/core/provider_registry.cpp
	src/core/format.cpp
	src/core/duration.cpp
	src/wmi/wmi_connection.cpp
	src/wmi/wmi_row.cpp
	src/wmi/wmi_date_time.cpp
	${PROVIDER_SOURCES}
	src/sysinfo.manifest
)

target_include_directories(sysinfo PRIVATE src)

target_compile_definitions(sysinfo PRIVATE UNICODE _UNICODE)

target_link_libraries(sysinfo PRIVATE
	ole32
	oleaut32
	wbemuuid
	advapi32
)

# RTTI is unused (no dynamic_cast/typeid), so drop it; /Gy plus the linker's /OPT:REF and /OPT:ICF let unused and duplicate functions be discarded/folded; /GL plus /LTCG do whole-program optimization across translation units. All Release-only since none of this matters for Debug.
target_compile_options(sysinfo PRIVATE
	$<$<CONFIG:Release>:/GR->
	$<$<CONFIG:Release>:/Gy>
	$<$<CONFIG:Release>:/GL>
)
target_link_options(sysinfo PRIVATE
	$<$<CONFIG:Release>:/LTCG>
	$<$<CONFIG:Release>:/OPT:REF>
	$<$<CONFIG:Release>:/OPT:ICF>
)
