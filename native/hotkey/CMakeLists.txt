cmake_minimum_required(VERSION 3.10)
project(hotkey LANGUAGES C)

find_package(X11 REQUIRED)

add_library(hotkey SHARED
    hotkey_wrapper.c
    hotkey_wrapper.h
)

target_link_libraries(hotkey PRIVATE X11::X11)

set_target_properties(hotkey PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
)
