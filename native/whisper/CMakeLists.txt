cmake_minimum_required(VERSION 3.13)
project(whisper_native LANGUAGES CXX C)

# Enable Vulkan
option(WHISPER_VULKAN "Use Vulkan" ON)

if (WHISPER_VULKAN)
    find_package(Vulkan REQUIRED)
    add_definitions(-DGGML_USE_VULKAN)
    message(STATUS "Vulkan enabled")
endif()

# Set output directory
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

set(WHISPER_DIR ${CMAKE_CURRENT_SOURCE_DIR}/whisper.cpp)

# Include directories
include_directories(
    ${WHISPER_DIR}/include
    ${WHISPER_DIR}/ggml/include
    ${WHISPER_DIR}/ggml/src
    ${WHISPER_DIR}/ggml/src/ggml-cpu
    ${WHISPER_DIR}/ggml/src/ggml-vulkan
    ${WHISPER_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}
)

if (WHISPER_VULKAN)
    include_directories(${Vulkan_INCLUDE_DIRS})
endif()

# Source files
set(WHISPER_SOURCES
    ${WHISPER_DIR}/ggml/src/ggml.c
    ${WHISPER_DIR}/ggml/src/ggml-alloc.c
    ${WHISPER_DIR}/ggml/src/ggml-backend.cpp
    ${WHISPER_DIR}/ggml/src/ggml-backend-reg.cpp
    ${WHISPER_DIR}/ggml/src/ggml-quants.c
    ${WHISPER_DIR}/ggml/src/ggml-threading.cpp
    ${WHISPER_DIR}/ggml/src/ggml-opt.cpp
    ${WHISPER_DIR}/ggml/src/gguf.cpp
    # CPU Backend core
    ${WHISPER_DIR}/ggml/src/ggml-cpu/ggml-cpu.c
    ${WHISPER_DIR}/ggml/src/ggml-cpu/ggml-cpu.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/vec.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/ops.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/quants.c
    ${WHISPER_DIR}/ggml/src/ggml-cpu/repack.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/traits.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/hbm.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/binary-ops.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/unary-ops.cpp
    # CPU Backend architecture-specific (x86)
    ${WHISPER_DIR}/ggml/src/ggml-cpu/arch/x86/quants.c
    ${WHISPER_DIR}/ggml/src/ggml-cpu/arch/x86/repack.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/arch/x86/cpu-feats.cpp
    # CPU Backend AMX
    ${WHISPER_DIR}/ggml/src/ggml-cpu/amx/amx.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/amx/mmq.cpp
    # Llamafile optimizations
    ${WHISPER_DIR}/ggml/src/ggml-cpu/llamafile/sgemm.cpp
    # Whisper core
    ${WHISPER_DIR}/src/whisper.cpp
    whisper_wrapper.cpp
)

if (WHISPER_VULKAN)
    list(APPEND WHISPER_SOURCES ${WHISPER_DIR}/ggml/src/ggml-vulkan/ggml-vulkan.cpp)
    file(GLOB VULKAN_SHADER_SOURCES "${WHISPER_DIR}/ggml/src/ggml-vulkan/*.comp.cpp")
    list(APPEND WHISPER_SOURCES ${VULKAN_SHADER_SOURCES})
endif()

# Add shared library
add_library(whisper SHARED ${WHISPER_SOURCES})

# Use the rename header for all sources that might have symbol conflicts
set(RENAMED_SOURCES
    ${WHISPER_DIR}/ggml/src/ggml.c
    ${WHISPER_DIR}/ggml/src/ggml-alloc.c
    ${WHISPER_DIR}/ggml/src/ggml-backend.cpp
    ${WHISPER_DIR}/ggml/src/ggml-backend-reg.cpp
    ${WHISPER_DIR}/ggml/src/ggml-quants.c
    ${WHISPER_DIR}/ggml/src/ggml-cpu/ggml-cpu.c
    ${WHISPER_DIR}/ggml/src/ggml-cpu/ggml-cpu.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/vec.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/ops.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/quants.c
    ${WHISPER_DIR}/ggml/src/ggml-cpu/repack.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/traits.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/hbm.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/binary-ops.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/unary-ops.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/arch/x86/quants.c
    ${WHISPER_DIR}/ggml/src/ggml-cpu/arch/x86/repack.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/amx/amx.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/amx/mmq.cpp
    ${WHISPER_DIR}/ggml/src/ggml-cpu/llamafile/sgemm.cpp
    ${WHISPER_DIR}/src/whisper.cpp
)

if (WHISPER_VULKAN)
    list(APPEND RENAMED_SOURCES ${WHISPER_DIR}/ggml/src/ggml-vulkan/ggml-vulkan.cpp)
    list(APPEND RENAMED_SOURCES ${VULKAN_SHADER_SOURCES})
endif()

foreach(source ${RENAMED_SOURCES})
    set_source_files_properties(${source} PROPERTIES COMPILE_FLAGS "-include ${CMAKE_CURRENT_SOURCE_DIR}/rename_whisper.h")
endforeach()

# Compile definitions
target_compile_definitions(whisper PRIVATE 
    WHISPER_SHARED 
    WHISPER_BUILD
    GGML_SHARED
    GGML_BUILD
    GGML_USE_CPU
    GGML_USE_LLAMAFILE
    GGML_VERSION="1"
    GGML_COMMIT="unknown"
    WHISPER_VERSION="1.8.1"
    _GNU_SOURCE
)

# Standard flags
target_compile_features(whisper PUBLIC cxx_std_17)
if (NOT MSVC)
    # Enable essential SIMD flags for x86_64
    target_compile_options(whisper PRIVATE -Wall -Wextra -O3 -mavx -mavx2 -mfma -mf16c)
endif()

# Link dependencies
find_package(Threads REQUIRED)
target_link_libraries(whisper PRIVATE Threads::Threads m ${CMAKE_DL_LIBS})

if (WHISPER_VULKAN)
    target_link_libraries(whisper PRIVATE Vulkan::Vulkan)
endif()

# Set the library name
set_target_properties(whisper PROPERTIES 
    OUTPUT_NAME "whisper"
    PREFIX "lib"
)
