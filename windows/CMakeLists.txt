# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "video_player_win")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "video_player_win_plugin")

# Include custom dependencies management
include(${CMAKE_CURRENT_SOURCE_DIR}/dependencies.cmake)

######## Jacky {
# download nuget.exe (Microsoft) and Microsoft WebView2 SDK
# ref: https://github.com/jnschulze/flutter-webview-windows/blob/main/windows/CMakeLists.txt

set(NUGET_URL https://dist.nuget.org/win-x86-commandline/v5.10.0/nuget.exe)
set(NUGET_SHA256 852b71cc8c8c2d40d09ea49d321ff56fd2397b9d6ea9f96e532530307bbbafd3)

set(WIL_VERSION "1.0.220914.1")

find_program(NUGET nuget)
if(NOT NUGET)
  set(NUGET ${CMAKE_BINARY_DIR}/nuget.exe)

  if (NOT EXISTS ${NUGET})
    message(NOTICE "Nuget is not installed.\nStart downloading nuget. Please wait...")
    file(DOWNLOAD ${NUGET_URL} ${NUGET})
  endif()

  file(SHA256 ${NUGET} NUGET_DL_HASH)
  if (NOT NUGET_DL_HASH STREQUAL NUGET_SHA256)
    message(FATAL_ERROR "Integrity check for ${NUGET} failed.")
  endif()
endif()

add_custom_target(${PROJECT_NAME}_DEPENDENCIES_DOWNLOAD ALL)
add_custom_command(
  TARGET ${PROJECT_NAME}_DEPENDENCIES_DOWNLOAD PRE_BUILD
  COMMAND ${NUGET} install Microsoft.Windows.ImplementationLibrary -Version ${WIL_VERSION} -ExcludeVersion -OutputDirectory ${CMAKE_BINARY_DIR}/packages
  DEPENDS ${NUGET}
)

include_directories("${CMAKE_CURRENT_SOURCE_DIR}/DX11VideoRenderer")
AUX_SOURCE_DIRECTORY(DX11VideoRenderer DX11VideoRenderer_Sources)
######## Jacky }

# Any new source files that you add to the plugin should be added here.
list(APPEND PLUGIN_SOURCES
  "video_player_win_plugin.cpp"
  "video_player_win_plugin.h"
)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED
  "include/video_player_win/video_player_win_plugin_c_api.h"
  "video_player_win_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
  "my_grabber_player.cpp" #Jacky
  ${DX11VideoRenderer_Sources} #Jacky
)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})

# Jacky {
target_link_libraries(${PLUGIN_NAME} PRIVATE ${CMAKE_BINARY_DIR}/packages/Microsoft.Windows.ImplementationLibrary/build/native/Microsoft.Windows.ImplementationLibrary.targets)
# Jacky }

# Add dependency on our custom dependencies
add_dependencies(${PLUGIN_NAME} video_player_win_all_dependencies)

# Suppress missing dependency warnings for Windows.Devices.Printers.Extensions.dll
suppress_dependency_warnings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins. This should not be removed; any symbols that should be
# exported should be explicitly exported with the FLUTTER_PLUGIN_EXPORT macro.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Source include directories and library dependencies. Add any plugin-specific
# dependencies here.
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

# Fix for unresolved external symbols in the C++ standard library
target_link_libraries(${PLUGIN_NAME} PRIVATE 
  flutter 
  flutter_wrapper_plugin
  mfplat.lib
  mfuuid.lib
  d3d11.lib
  dxgi.lib
  shlwapi.lib
  windowsapp
)

# Ensure proper C++ standard library linking
if(MSVC)
  # Force static linking of the C++ runtime library to avoid issues with firebase_firestore
  set_target_properties(${PLUGIN_NAME} PROPERTIES
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
  
  # Add specific compiler flags to address linking issues
  target_compile_options(${PLUGIN_NAME} PRIVATE 
    "/Zc:__cplusplus" # Enable correct __cplusplus macro
    "/EHsc"           # Enable standard C++ exception handling
    "/permissive-"    # Enforce strict standard compliance
  )
endif()

# Add Windows 10 SDK libraries
find_path(MEDIA_FOUNDATION_DIR
  NAMES Windows.Media.h
  PATHS "${CMAKE_SYSTEM_INCLUDE_PATH}"
  PATH_SUFFIXES "um"
)

if(MEDIA_FOUNDATION_DIR)
  target_include_directories(${PLUGIN_NAME} PRIVATE "${MEDIA_FOUNDATION_DIR}")
endif()

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(video_player_win_bundled_libraries
  ""
  PARENT_SCOPE
)

# Firebase compatibility fix - helps resolve the "__std_find_end_1" linking issue
if(DEFINED firebase_firestore_bundled_libraries OR DEFINED firebase_core_bundled_libraries)
  message(STATUS "Detected Firebase in the project, applying compatibility fixes")
  
  # When firebase is used, ensure consistent runtime library
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
  
  # Force consistent C++ standard across all libraries
  set(CMAKE_CXX_STANDARD 17)
  set(CMAKE_CXX_STANDARD_REQUIRED ON)
endif()
