cmake_minimum_required(VERSION 3.13)
project(vad_native LANGUAGES CXX C)

set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

# Find ONNX Runtime
# We assume it's in /usr/include/onnxruntime/
include_directories(/usr/include/onnxruntime)

# Source files
set(VAD_SOURCES
    vad_wrapper.cpp
    vad_wrapper.h
)

# Add shared library
add_library(vad SHARED ${VAD_SOURCES})

# Link dependencies
# We need to link against libonnxruntime.so
# It's usually in /usr/lib64/ or /usr/lib/
find_library(ONNXRUNTIME_LIB onnxruntime)
if(NOT ONNXRUNTIME_LIB)
    message(FATAL_ERROR "libonnxruntime not found")
endif()

target_link_libraries(vad PRIVATE ${ONNXRUNTIME_LIB} m)

# Standard flags
target_compile_features(vad PUBLIC cxx_std_14)
if (NOT MSVC)
    target_compile_options(vad PRIVATE -Wall -Wextra -O3 -mavx -mavx2 -mfma -mf16c)
endif()

# Set the library name
set_target_properties(vad PROPERTIES 
    OUTPUT_NAME "vad"
    PREFIX "lib"
)
