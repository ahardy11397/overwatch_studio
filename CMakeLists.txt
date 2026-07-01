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
# FFmpeg - vcpkg doesn't provide CMake config, use find_library instead
find_path(FFMPEG_AVFORMAT_INCLUDE_DIR NAMES libavformat/avformat.h
    HINTS "${CMAKE_BINARY_DIR}/vcpkg_installed/x64-windows/include"
    REQUIRED)
find_library(FFMPEG_AVFORMAT_LIBRARY NAMES avformat
    HINTS "${CMAKE_BINARY_DIR}/vcpkg_installed/x64-windows/lib"
    REQUIRED)
find_library(FFMPEG_AVCODEC_LIBRARY NAMES avcodec
    HINTS "${CMAKE_BINARY_DIR}/vcpkg_installed/x64-windows/lib"
    REQUIRED)
find_library(FFMPEG_AVUTIL_LIBRARY NAMES avutil
    HINTS "${CMAKE_BINARY_DIR}/vcpkg_installed/x64-windows/lib"
    REQUIRED)
find_library(FFMPEG_SWSCALE_LIBRARY NAMES swscale
    HINTS "${CMAKE_BINARY_DIR}/vcpkg_installed/x64-windows/lib"
    REQUIRED)

add_library(FFMPEG::avformat UNKNOWN IMPORTED)
set_target_properties(FFMPEG::avformat PROPERTIES
    IMPORTED_LOCATION "${FFMPEG_AVFORMAT_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${FFMPEG_AVFORMAT_INCLUDE_DIR}"
)
add_library(FFMPEG::avcodec UNKNOWN IMPORTED)
set_target_properties(FFMPEG::avcodec PROPERTIES
    IMPORTED_LOCATION "${FFMPEG_AVCODEC_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${FFMPEG_AVFORMAT_INCLUDE_DIR}"
)
add_library(FFMPEG::avutil UNKNOWN IMPORTED)
set_target_properties(FFMPEG::avutil PROPERTIES
    IMPORTED_LOCATION "${FFMPEG_AVUTIL_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${FFMPEG_AVFORMAT_INCLUDE_DIR}"
)
add_library(FFMPEG::swscale UNKNOWN IMPORTED)
set_target_properties(FFMPEG::swscale PROPERTIES
    IMPORTED_LOCATION "${FFMPEG_SWSCALE_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${FFMPEG_AVFORMAT_INCLUDE_DIR}"
)
message(STATUS "Found FFmpeg: ${FFMPEG_AVFORMAT_LIBRARY}")

# oscpack - vcpkg only ships release builds, use for both Debug and Release
# ponytail: all-config oscpack, install debug variant if needed later
add_library(oscpack::oscpack UNKNOWN IMPORTED)
set_target_properties(oscpack::oscpack PROPERTIES
    IMPORTED_LOCATION "${CMAKE_BINARY_DIR}/vcpkg_installed/x64-windows/lib/oscpack.lib"
    IMPORTED_LOCATION_DEBUG "${CMAKE_BINARY_DIR}/vcpkg_installed/x64-windows/lib/oscpack.lib"
    INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_BINARY_DIR}/vcpkg_installed/x64-windows/include"
)
message(STATUS "Found oscpack: ${OSCPACK_LIBRARY}")

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

target_link_libraries(overwatch_engine INTERFACE
    FFMPEG::avformat
    FFMPEG::avcodec
    FFMPEG::avutil
    FFMPEG::swscale
)

# Compiler Optimizations for MSVC & Clang/GCC
if(MSVC)
    target_compile_options(overwatch_engine INTERFACE
        $<$<CONFIG:Release>:/O2>   # Maximum Speed Optimization (Release only)
        $<$<CONFIG:Release>:/Ot>   # Favor Fast Code (Release only)
        $<$<CONFIG:Release>:/GL>   # LTCG (Release only)
        /fp:fast        # Fast Floating-Point Math Model
        /arch:AVX2      # Auto-Vectorize AVX2 Instructions
        /Gw             # Optimize Global Data (linker optimization)
        /Gy             # Enable Function-Level Linking
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
    src/core/audio/WindowsProcessCapture.cpp
    src/core/audio/WindowsProcessCapture.h
    src/core/video/VideoEngineCore.cpp
    src/core/video/FFmpegCaptureSource.cpp
    src/core/video/FFmpegCaptureSource.h
    src/core/video/VideoCaptureManager.cpp
    src/core/video/VideoCaptureManager.h
    src/ui/LocalMediaDeck.cpp
    src/ui/LocalMediaDeck.h
    src/core/control/ShowfileManager.cpp
    src/core/control/ShowfileManager.h
    src/core/control/ExternalControlSurfaceManager.cpp
    src/core/control/ExternalControlSurfaceManager.h
    src/core/control/WindowStateStore.h
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
    Qt6::Core
    Qt6::Gui
    oscpack::oscpack
    ws2_32
    winmm
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
    src/ui/LocalMediaDeck.cpp
    src/ui/LocalMediaDeck.h
    src/core/control/ShowfileManager.cpp
    src/core/control/ShowfileManager.h
    src/core/control/ExternalControlSurfaceManager.cpp
    src/core/control/ExternalControlSurfaceManager.h
    src/core/control/WindowStateStore.h
    src/core/video/FFmpegCaptureSource.cpp
    src/core/video/FFmpegCaptureSource.h
    src/core/video/VideoCaptureManager.cpp
    src/core/video/VideoCaptureManager.h
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
    oscpack::oscpack
    ws2_32
    winmm
)

set_target_properties(overwatch_studio PROPERTIES WIN32_EXECUTABLE ON)
