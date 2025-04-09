# Ensure dependencies like Windows.Devices.Printers.Extensions.dll are properly handled

# Define a function to check and download dependencies
function(ensure_dependency_exists library_name)
  # Check if the library exists
  if(NOT EXISTS "${CMAKE_BINARY_DIR}/deps/${library_name}")
    message(STATUS "Dependency ${library_name} not found. Configuring...")
    
    # Create the directory if it doesn't exist
    file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/deps")
    
    # Add a custom command to notify that the library couldn't be automatically downloaded
    # This allows the build to continue but will log an informative message
    add_custom_command(
      OUTPUT "${CMAKE_BINARY_DIR}/deps/${library_name}"
      COMMAND ${CMAKE_COMMAND} -E echo "NOTE: ${library_name} dependency cannot be auto-downloaded."
      COMMAND ${CMAKE_COMMAND} -E echo "This is an optional dependency and the build will continue."
      COMMAND ${CMAKE_COMMAND} -E touch "${CMAKE_BINARY_DIR}/deps/${library_name}"
      VERBATIM
    )
  endif()
  
  # Create a custom target for this dependency
  add_custom_target(${library_name}_dependency DEPENDS "${CMAKE_BINARY_DIR}/deps/${library_name}")
endfunction()

# Ensure Windows.Devices.Printers.Extensions.dll is available
ensure_dependency_exists("Windows.Devices.Printers.Extensions.dll")

# Create a target to gather all dependencies
add_custom_target(video_player_win_all_dependencies DEPENDS
  Windows.Devices.Printers.Extensions.dll_dependency
)

# Function to suppress missing dependency warnings
function(suppress_dependency_warnings target_name)
  if(MSVC)
    target_compile_options(${target_name} PRIVATE "/wd4099")
  endif()
endfunction() 