cmake_minimum_required(VERSION 3.25)
project(overwatch_studio VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# Configure output directories
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

# Find Packages via vcpkg
find_path(SOXR_INCLUDE_DIR NAMES soxr.h REQUIRED)
find_library(SOXR_LIBRARY NAMES soxr REQUIRED)

add_library(soxr::soxr UNKNOWN IMPORTED)
set_target_properties(soxr::soxr PROPERTIES
    IMPORTED_LOCATION "${SOXR_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${SOXR_INCLUDE_DIR}"
)
message(STATUS "Found soxr: ${SOXR_LIBRARY}")
find_package(simdjson REQUIRED)
find_package(libzip REQUIRED)
find_package(GTest REQUIRED)
find_package(readerwriterqueue CONFIG REQUIRED)
find_package(SQLite3 REQUIRED)
find_package(Qt6 COMPONENTS Core Gui Qml Quick QuickControls2 REQUIRED)

# If JUCE is available as a submodule, compile it. Otherwise configure headers mock.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/libs/juce/CMakeLists.txt")
    add_subdirectory(libs/juce)
else()
    message(STATUS "JUCE submodule not found. Creating a local header mock configuration for standalone testing.")
endif()

# Define engine library target
add_library(overwatch_engine INTERFACE)

target_include_directories(overwatch_engine INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src/core/audio>
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src/core/control>
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src/core/video>
)

target_link_libraries(overwatch_engine INTERFACE
    soxr::soxr
    simdjson::simdjson
    libzip::zip
)

# Compiler Optimizations for MSVC & Clang/GCC
if(MSVC)
    target_compile_options(overwatch_engine INTERFACE
        /O2             # Maximum Speed Optimization
        /Ot             # Favor Fast Code
        /fp:fast        # Fast Floating-Point Math Model
        /arch:AVX2      # Auto-Vectorize AVX2 Instructions
        /Gw             # Optimize Global Data (linker optimization)
        /Gy             # Enable Function-Level Linking
        /GL             # Enable Whole Program Optimization (LTCG)
    )
else()
    target_compile_options(overwatch_engine INTERFACE
        -Ofast
        -mavx2
        -mfma
        -ffast-math
        -ftree-vectorize
        -Wno-padded
        -Wall
        -Wextra
        -Wpedantic
        -Wconversion
    )
endif()

# RealtimeSanitizer (RTSan) Compiler Configuration
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    target_compile_options(overwatch_engine INTERFACE -fsanitize=realtime)
    target_link_options(overwatch_engine INTERFACE -fsanitize=realtime)
    add_compile_definitions(__SANITIZE_REALTIME=1)
    message(STATUS "RealtimeSanitizer (RTSan) instrumentation enabled for overwatch_engine.")
endif()

# --- Automated Testing Suite (GoogleTest) ---
enable_testing()
add_executable(AudioEngineTests
    tests/AudioEngineTests.cpp
    tests/DynamicAudioEngineTests.cpp
    tests/ControlEngineTests.cpp
    tests/VideoEngineTests.cpp
    src/core/audio/WASAPIDeviceWorker.cpp
    src/core/audio/WASAPIDeviceWorker.h
)
target_link_libraries(AudioEngineTests PRIVATE
    overwatch_engine
    GTest::gtest
    GTest::gtest_main
    readerwriterqueue::readerwriterqueue
    SQLite3::SQLite3
    libzip::zip
    simdjson::simdjson
    ole32
    mmdevapi
)
add_test(NAME AudioEngineTests COMMAND AudioEngineTests)


# --- MVP Executable ---
add_executable(overwatch_studio 
    src/main.cpp
    src/ui/AudioEngineBridge.cpp
    src/ui/AudioEngineBridge.h
    src/ui/VideoCanvasMock.cpp
    src/ui/VideoCanvasMock.h
    src/ui/ShowBuilderBridge.cpp
    src/ui/ShowBuilderBridge.h
    src/core/audio/WindowsProcessCapture.cpp
    src/core/audio/WindowsProcessCapture.h
    src/core/audio/WASAPIDeviceWorker.cpp
    src/core/audio/WASAPIDeviceWorker.h
)

qt_add_qml_module(overwatch_studio
    URI overwatch_studio
    VERSION 1.0
    QML_FILES src/ui/Main.qml
)

target_link_libraries(overwatch_studio PRIVATE
    overwatch_engine
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2
    readerwriterqueue::readerwriterqueue
    SQLite3::SQLite3
    libzip::zip
    simdjson::simdjson
    ole32
    mmdevapi
)

set_target_properties(overwatch_studio PROPERTIES WIN32_EXECUTABLE ON)
